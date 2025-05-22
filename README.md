#!/bin/bash

# === CONFIGURATION ===
CLUSTER_URL="https://api.YOUR-CLUSTER.openshift.com:6443"
TOKEN="sha256~YOUR_TOKEN_HERE"
APP_NAME="myapp-tomcat"
PROJECT="myproject"  # Change to your OpenShift project

# === LOGIN ===
echo "Logging into OpenShift..."
oc login $CLUSTER_URL --token=$TOKEN

# === SET PROJECT ===
echo "Using project: $PROJECT"
oc project $PROJECT || oc new-project $PROJECT

# === CREATE DOCKERFILE FOR TOMCAT DEPLOYMENT ===
echo "Preparing Dockerfile and build context..."
cat <<EOF > Dockerfile
FROM tomcat:9.0-jdk17
COPY myapp.war /usr/local/tomcat/webapps/
COPY application.properties /usr/local/tomcat/conf/
EOF

# === CREATE NEW BUILD ===
echo "Creating new binary build..."
oc delete bc $APP_NAME --ignore-not-found
oc new-build --name=$APP_NAME --binary --strategy=docker

# === START BUILD ===
echo "Starting build..."
oc start-build $APP_NAME --from-dir=. --follow

# === DEPLOY ===
echo "Deploying the app..."
oc delete dc $APP_NAME --ignore-not-found
oc new-app $APP_NAME

# === EXPOSE ROUTE ===
echo "Exposing the application..."
oc expose svc/$APP_NAME

# === DONE ===
ROUTE=$(oc get route $APP_NAME -o jsonpath='{.spec.host}')
echo "Application deployed at: http://$ROUTE"
