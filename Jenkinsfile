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

        /*
         * DO NOT set MSYS_NO_PATHCONV globally.
         *
         * Windows Jenkins + Git Bash needs normal path conversion for
         * docker build.
         *
         * Enable MSYS_NO_PATHCONV=1 only around docker run commands
         * that contain Linux container paths such as /app.
         */
    }

    options {
        timestamps()

        disableConcurrentBuilds()

        buildDiscarder(
            logRotator(numToKeepStr: '30')
        )
    }

    stages {

        /*
         * ================================================================
         * CHECKOUT
         * ================================================================
         */

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


        /*
         * ================================================================
         * VALIDATE VERSION
         * ================================================================
         */

        stage('Validate Version') {
            steps {

                script {

                    if (!params.APP_VERSION?.trim()) {
                        error(
                            'APP_VERSION parameter is required, e.g. APP_VERSION=7.9'
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


        /*
         * ================================================================
         * UNIT / APPLICATION TEST
         * ================================================================
         */

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

                    /*
                     * Windows Jenkins uses Git Bash.
                     *
                     * Without MSYS_NO_PATHCONV=1 Git Bash can transform:
                     *
                     *     /app
                     *
                     * into:
                     *
                     *     C:/Program Files/Git/app
                     *
                     * which breaks Docker's container working directory.
                     */

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


        /*
         * ================================================================
         * DOCKER BUILD
         * ================================================================
         */

        stage('Docker Build') {
            steps {

                script {

                    def buildOutput = sh(
                        script: """
                            set -e

                            scripts/build-image.sh \
                                '${params.APP_VERSION}' \
                                '${env.GIT_COMMIT_SHA}'
                        """,
                        returnStdout: true
                    ).trim()

                    if (!buildOutput) {
                        error('Docker build script returned no output.')
                    }

                    def lines = buildOutput.readLines()

                    /*
                     * build-image.sh must print the final image tag
                     * as its LAST line.
                     */
                    env.IMAGE_TAG = lines[-1].trim()

                    if (!env.IMAGE_TAG) {
                        error('Docker build did not return an image tag.')
                    }

                    /*
                     * Basic image-tag sanity check.
                     */
                    if (!env.IMAGE_TAG.startsWith("${env.IMAGE_NAME}:")) {
                        error(
                            "Invalid image tag returned by build-image.sh: ${env.IMAGE_TAG}"
                        )
                    }

                    echo "Built image: ${env.IMAGE_TAG}"
                }
            }
        }


        /*
         * ================================================================
         * DOCKER IMAGE VALIDATION
         * ================================================================
         */

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


        /*
         * ================================================================
         * START CANDIDATE
         * ================================================================
         */

        stage('Start Candidate') {
            steps {

                /*
                 * Jenkins credential setup:
                 *
                 * Create:
                 *
                 *   Kind: Secret text
                 *   ID: orders-api-secret
                 *
                 * The value should be the actual value of
                 * ORDERS_API_SECRET.
                 *
                 * Jenkins injects the secret into:
                 *
                 *   ORDERS_API_SECRET_VALUE
                 *
                 * We create the temporary env file expected by
                 * start-candidate.sh.
                 *
                 * The file is deleted in the finally block.
                 */

                withCredentials([
                    string(
                        credentialsId: 'orders-api-secret',
                        variable: 'ORDERS_API_SECRET_VALUE'
                    )
                ]) {

                    script {

                        def secretDir =
                            "${env.WORKSPACE}/scripts/secrets"

                        def secretFile =
                            "${secretDir}/orders-api.env"

                        try {

                            /*
                             * IMPORTANT:
                             *
                             * Do not interpolate the secret into a
                             * Groovy triple-quoted string.
                             *
                             * Let the shell expand the Jenkins-provided
                             * environment variable.
                             */

                            sh '''
                                set -e

                                mkdir -p "$WORKSPACE/scripts/secrets"

                                printf '%s\\n' \
                                    "ORDERS_API_SECRET=$ORDERS_API_SECRET_VALUE" \
                                    > "$WORKSPACE/scripts/secrets/orders-api.env"

                                chmod 600 \
                                    "$WORKSPACE/scripts/secrets/orders-api.env"

                                echo "Temporary deployment secret file created."
                            '''

                            def out = sh(
                                script: """
                                    set -e

                                    scripts/start-candidate.sh \
                                        '${env.IMAGE_TAG}' \
                                        '${params.APP_VERSION}' \
                                        '${env.GIT_COMMIT_SHA}'
                                """,
                                returnStdout: true
                            ).trim()

                            if (!out) {
                                error(
                                    'start-candidate.sh returned no output.'
                                )
                            }

                            echo out

                            /*
                             * Parse deployment metadata returned by
                             * start-candidate.sh.
                             *
                             * Never copy ORDERS_API_SECRET into Jenkins
                             * environment variables.
                             */

                            out.split('\\n').each { line ->

                                if (line.contains('=')) {

                                    def parts = line.split('=', 2)

                                    if (parts.length == 2) {

                                        def key =
                                            parts[0].trim()

                                        def value =
                                            parts[1].trim()

                                        if (key &&
                                            key != 'ORDERS_API_SECRET') {

                                            env."${key}" = value
                                        }
                                    }
                                }
                            }

                            /*
                             * Verify that the candidate metadata needed
                             * by the following stages was actually returned.
                             */

                            if (!env.CURRENT_COLOR) {
                                error(
                                    'start-candidate.sh did not return CURRENT_COLOR.'
                                )
                            }

                            if (!env.CANDIDATE_COLOR) {
                                error(
                                    'start-candidate.sh did not return CANDIDATE_COLOR.'
                                )
                            }

                            if (!env.CANDIDATE_NAME) {
                                error(
                                    'start-candidate.sh did not return CANDIDATE_NAME.'
                                )
                            }

                            if (!env.CANDIDATE_PORT) {
                                error(
                                    'start-candidate.sh did not return CANDIDATE_PORT.'
                                )
                            }

                        } finally {

                            /*
                             * Always remove the temporary secret file.
                             */

                            sh '''
                                rm -f \
                                    "$WORKSPACE/scripts/secrets/orders-api.env" \
                                    || true
                            '''

                            echo "Temporary deployment secret file removed."
                        }
                    }
                }

                echo "CURRENT color: ${env.CURRENT_COLOR} | CANDIDATE color: ${env.CANDIDATE_COLOR} (port ${env.CANDIDATE_PORT})"
            }
        }


        /*
         * ================================================================
         * CONTAINER VALIDATION
         * ================================================================
         */

        stage('Container Validation') {
            steps {

                sh """
                    scripts/container-validation.sh \
                        '${env.CANDIDATE_NAME}' \
                        '${env.CANDIDATE_PORT}'
                """
            }
        }


        /*
         * ================================================================
         * APPLICATION HEALTH CHECK
         * ================================================================
         */

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


        /*
         * ================================================================
         * INTEGRATION CHECK
         * ================================================================
         */

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


        /*
         * ================================================================
         * TRAFFIC SWITCH
         * ================================================================
         */

        stage('Traffic Switch') {
            steps {

                sh """
                    scripts/switch-traffic.sh \
                        '${env.CANDIDATE_COLOR}' \
                        '${params.APP_VERSION}'
                """
            }
        }


        /*
         * ================================================================
         * OLD VERSION CLEANUP
         * ================================================================
         */

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


        /*
         * ================================================================
         * DEPLOYMENT VERIFICATION
         * ================================================================
         */

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


    /*
     * ====================================================================
     * POST ACTIONS
     * ====================================================================
     */

    post {

        failure {

            script {

                echo "Build FAILED. Production traffic was not intentionally switched."

                /*
                 * If candidate metadata is available, remove/rollback
                 * the candidate without touching production traffic.
                 */

                if (env.CANDIDATE_COLOR &&
                    env.CURRENT_COLOR) {

                    sh """
                        scripts/rollback-candidate.sh \
                            '${env.CANDIDATE_COLOR}' \
                            '${env.CURRENT_COLOR}' \
                            || true
                    """

                } else {

                    echo "No candidate color was available for rollback."
                }
            }

            echo "Diagnostic logs and container state were captured above."
        }


        success {

            echo "========================================="
            echo "BLUE/GREEN DEPLOYMENT SUCCESSFUL"
            echo "========================================="
            echo "Version        : ${params.APP_VERSION}"
            echo "Commit         : ${env.GIT_COMMIT_SHA}"
            echo "Active Color   : ${env.CANDIDATE_COLOR}"
            echo "Candidate Port : ${env.CANDIDATE_PORT}"
            echo "Production Port: 8080"
            echo "========================================="
        }


        always {

            echo "Final orders-* container state:"

            sh '''
                docker ps \
                    --filter name=orders- \
                    --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}' \
                    || true
            '''
        }
    }
}

