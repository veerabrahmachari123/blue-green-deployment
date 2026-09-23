// orders-api blue-green deployment pipeline
//
// A green build here means: a new immutably-tagged image was built from a
// known Git commit, started alongside the currently-live color, proven
// healthy AND functionally correct (DB reachable, identity verified), and
// ONLY THEN promoted by switching router traffic.
//
// Any failure before promotion leaves production untouched.

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

        // IMPORTANT:
        // Do NOT set MSYS_NO_PATHCONV globally.
        //
        // Docker commands that use Linux/container paths such as:
        //     -w /app
        //
        // need MSYS_NO_PATHCONV=1.
        //
        // But docker build on Windows needs Git Bash to convert:
        //     /c/ProgramData/...
        //
        // into:
        //     C:/ProgramData/...
        //
        // Therefore MSYS_NO_PATHCONV is enabled only on the
        // docker run command in the Unit/Application Test stage.

        SECRET_ENV_FILE = "${WORKSPACE}/scripts/secrets/orders-api.env"
    }

    options {
        timestamps()

        disableConcurrentBuilds()

        buildDiscarder(
            logRotator(numToKeepStr: '30')
        )
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
                        error(
                            "APP_VERSION parameter is required, e.g. APP_VERSION=7.9"
                        )
                    }
                }

                sh '''
                    chmod +x scripts/*.sh
                '''

                sh """
                    scripts/validate-version.sh \
                        '${params.APP_VERSION}' \
                        '${env.GIT_COMMIT_SHA}'
                """
            }
        }

        stage('Unit/Application Test') {
            steps {

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

                    # IMPORTANT:
                    # This flag is scoped ONLY to docker run.
                    #
                    # The Jenkins agent uses Windows + Git Bash.
                    # Git Bash otherwise converts /app into:
                    #
                    # C:/Program Files/Git/app
                    #
                    # which causes Docker to reject the container
                    # working directory.

                    MSYS_NO_PATHCONV=1 docker run --rm \
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

                    // IMPORTANT:
                    // Do NOT pipe the build script through `tail`.
                    //
                    // A pipe can hide the exit code from docker build.
                    // build-image.sh now fails immediately when Docker
                    // fails and returns the immutable image tag on its
                    // final line.

                    def buildOutput = sh(
                        script: """
                            scripts/build-image.sh \
                                '${params.APP_VERSION}' \
                                '${env.GIT_COMMIT_SHA}'
                        """,
                        returnStdout: true
                    ).trim()

                    def outputLines = buildOutput.readLines()

                    if (outputLines.isEmpty()) {
                        error("Docker build script returned no output.")
                    }

                    env.IMAGE_TAG = outputLines[-1].trim()

                    if (!env.IMAGE_TAG) {
                        error("Docker build did not return an image tag.")
                    }

                    echo "Built image: ${env.IMAGE_TAG}"
                }
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

                    out.split('\\n').each { line ->

                        if (line.contains('=')) {

                            def parts = line.split('=', 2)

                            if (parts.length == 2) {
                                def key = parts[0].trim()
                                def value = parts[1].trim()

                                env."${key}" = value
                            }
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

                sh '''
                    KEEP_LAST_N=3 scripts/cleanup-images.sh
                '''
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

                    echo "Failure occurred before a candidate color was determined - no candidate to roll back."
                }
            }

            echo "Diagnostic logs and container state were captured above for this failure."
        }

        success {

            echo "Deployment SUCCESSFUL: version=${params.APP_VERSION} commit=${env.GIT_COMMIT_SHA} now live as ${env.CANDIDATE_COLOR} on port 8080."
        }

        always {

            sh '''
                docker ps \
                    --filter name=orders- \
                    --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}' \
                    || true
            '''
        }
    }
}