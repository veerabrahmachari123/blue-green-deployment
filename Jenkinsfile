// orders-api blue-green deployment pipeline
//
// A green build here means: a new immutably-tagged image was built from a
// known Git commit, started alongside the currently-live color, proven
// healthy AND functionally correct (DB reachable, identity verified), and
// ONLY THEN promoted by switching router traffic — with the previous
// color removed only after that promotion is confirmed. Any failure before
// promotion leaves production completely untouched.

pipeline {

    agent any

    parameters {
        string(
            name: 'APP_VERSION',
            defaultValue: '',
            description: 'Immutable version to deploy, e.g. 7.9. Required.'
        )
    }

    environment {
        IMAGE_NAME = 'orders-api'
        NETWORK_NAME = 'orders-network'
        ROUTER_CONTAINER = 'orders-router'
        DB_CONTAINER = 'orders-db'

        // IMPORTANT FOR WINDOWS JENKINS + GIT BASH
        //
        // Git Bash/MSYS automatically converts Unix-style paths such as
        // /app into Windows paths before passing them to Docker.
        //
        // Example of the broken behavior:
        //     -w /app
        // becomes:
        //     -w C:/Program Files/Git/app
        //
        // This causes Docker to fail with:
        // "the working directory 'C:/Program Files/Git/app' is invalid"
        //
        // Disable MSYS path conversion so Docker receives Unix container
        // paths exactly as intended.
        MSYS_NO_PATHCONV = '1'

        // Secret is bound to a file at runtime and never echoed.
        SECRET_ENV_FILE = "${WORKSPACE}/scripts/secrets/orders-api.env"
    }

    options {
        timestamps()

        // Prevent two deployments from racing each other / creating
        // uncontrolled duplicate candidate containers.
        disableConcurrentBuilds()

        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                script {
                    env.GIT_COMMIT_SHA = sh(
                        script: 'git rev-parse HEAD',
                        returnStdout: true
                    ).trim()

                    env.GIT_BRANCH_NAME = sh(
                        script: 'git rev-parse --abbrev-ref HEAD',
                        returnStdout: true
                    ).trim()
                }

                echo "Checked out commit ${env.GIT_COMMIT_SHA} on branch ${env.GIT_BRANCH_NAME}"
            }
        }

        stage('Validate Version') {
            steps {

                script {
                    if (!params.APP_VERSION?.trim()) {
                        error("APP_VERSION parameter is required, e.g. -PAPP_VERSION=7.9")
                    }
                }

                sh "chmod +x scripts/*.sh"

                sh """
                    scripts/validate-version.sh \
                        '${params.APP_VERSION}' \
                        '${env.GIT_COMMIT_SHA}'
                """
            }
        }

        stage('Unit/Application Test') {
            steps {

                // Runs inside a throwaway node:20-alpine container rather
                // than requiring Node.js to be installed on the Jenkins host.
                //
                // MSYS_NO_PATHCONV=1 is set globally above because this
                // Jenkins agent is running on Windows through Git Bash.
                //
                // Without it Git Bash changes:
                //
                //     -w /app
                //
                // into:
                //
                //     -w C:/Program Files/Git/app
                //
                // which causes Docker exit code 125.

                sh '''
                    set -e

                    echo "========================================="
                    echo "Running Unit/Application Tests"
                    echo "========================================="

                    echo "Jenkins workspace:"
                    echo "${WORKSPACE}"

                    if [ ! -d "${WORKSPACE}/app" ]; then
                        echo "ERROR: application directory does not exist:"
                        echo "${WORKSPACE}/app"
                        exit 1
                    fi

                    echo "Application directory found."

                    echo "Application files:"
                    ls -la "${WORKSPACE}/app"

                    echo "Running Node.js tests inside node:20-alpine..."

                    docker run --rm \
                        -v "${WORKSPACE}/app:/app" \
                        -w /app \
                        node:20-alpine \
                        node test.js

                    echo "========================================="
                    echo "Unit/Application Tests PASSED"
                    echo "========================================="
                '''
            }
        }

        stage('Docker Build') {
            steps {

                script {
                    env.IMAGE_TAG = sh(
                        script: """
                            scripts/build-image.sh \
                                '${params.APP_VERSION}' \
                                '${env.GIT_COMMIT_SHA}' | tail -n1
                        """,
                        returnStdout: true
                    ).trim()
                }

                echo "Built image: ${env.IMAGE_TAG}"
            }
        }

        stage('Docker Image Validation') {
            steps {

                sh """
                    scripts/validate-image.sh \
                        '${env.IMAGE_TAG}' \
                        '${params.APP_VERSION}' \
                        '${env.GIT_COMMIT_SHA}'
                """
            }
        }

        stage('Start Candidate') {
            steps {

                // On a real Jenkins controller the secret is bound from a
                // Credentials file binding, e.g.:
                //
                // withCredentials([
                //     file(
                //         credentialsId: 'orders-api-secret-env',
                //         variable: 'SECRET_ENV_FILE'
                //     )
                // ]) {
                //     ...
                // }
                //
                // Its contents never appear in the Jenkinsfile, SCM,
                // or console log.

                script {

                    def out = sh(
                        script: """
                            scripts/start-candidate.sh \
                                '${env.IMAGE_TAG}' \
                                '${params.APP_VERSION}' \
                                '${env.GIT_COMMIT_SHA}'
                        """,
                        returnStdout: true
                    ).trim()

                    echo out

                    out.split('\n').each { line ->

                        if (line.contains('=')) {

                            def (k, v) = line.split('=', 2)

                            env."${k}" = v
                        }
                    }
                }

                echo "CURRENT color: ${env.CURRENT_COLOR} | CANDIDATE color: ${env.CANDIDATE_COLOR} (port ${env.CANDIDATE_PORT})"
            }
        }

        stage('Container Validation') {
            steps {

                sh """
                    scripts/container-validation.sh \
                        '${env.CANDIDATE_NAME}' \
                        '${env.CANDIDATE_PORT}'
                """
            }
        }

        stage('Application Health Check') {
            steps {

                sh """
                    scripts/health-check.sh \
                        '${env.CANDIDATE_PORT}' \
                        '${env.CANDIDATE_NAME}' \
                        10 \
                        2
                """
            }
        }

        stage('Integration Check') {
            steps {

                sh """
                    scripts/integration-check.sh \
                        '${env.CANDIDATE_PORT}' \
                        '${params.APP_VERSION}' \
                        '${env.GIT_COMMIT_SHA}'
                """
            }
        }

        stage('Traffic Switch') {
            steps {

                sh """
                    scripts/switch-traffic.sh \
                        '${env.CANDIDATE_COLOR}' \
                        '${params.APP_VERSION}'
                """
            }
        }

        stage('Old Version Cleanup') {
            steps {

                sh """
                    scripts/cleanup-old.sh \
                        '${env.CURRENT_COLOR}'
                """

                sh """
                    KEEP_LAST_N=3 scripts/cleanup-images.sh
                """
            }
        }

        stage('Deployment Verification') {
            steps {

                sh """
                    scripts/deployment-verification.sh \
                        '${params.APP_VERSION}' \
                        '${env.GIT_COMMIT_SHA}' \
                        '${env.CANDIDATE_COLOR}'
                """

                archiveArtifacts(
                    artifacts: ".evidence/deployment-${params.APP_VERSION}.json",
                    allowEmptyArchive: false
                )
            }
        }
    }

    post {

        failure {

            script {

                echo "Build FAILED before/at stage '${env.STAGE_NAME}'. Rolling back candidate, leaving production untouched."

                if (env.CANDIDATE_COLOR && env.CURRENT_COLOR) {

                    sh """
                        scripts/rollback-candidate.sh \
                            '${env.CANDIDATE_COLOR}' \
                            '${env.CURRENT_COLOR}' || true
                    """

                } else {

                    echo "Failure occurred before a candidate color was determined (e.g. during Checkout/Validate/Build) - no candidate to roll back."
                }
            }

            echo "Diagnostic logs and container state were captured above for this failure (Phase 1/5/6 evidence)."
        }

        success {

            echo "Deployment SUCCESSFUL: version=${params.APP_VERSION} commit=${env.GIT_COMMIT_SHA} now live as ${env.CANDIDATE_COLOR} on port 8080."
        }

        always {

            sh """
                docker ps \
                    --filter name=orders- \
                    --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}' \
                    || true
            """
        }
    }
}