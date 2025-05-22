#!/bin/bash
set -e

# === CONFIGURATION ===
APP_NAME="my-tomcat-app"
PROJECT="myproject"
SRC_DIR="/path/to/your/app"  # <-- change this to where your Dockerfile and ROOT.war are
IMAGE_STREAM="$APP_NAME-image"
BUILD_CONFIG="$APP_NAME-build"
DEPLOYMENT_YAML="/tmp/deployment.yaml"

# === SELECT PROJECT ===
oc project $PROJECT

echo "[INFO] Creating ImageStream: $IMAGE_STREAM"
oc apply -f - <<EOF
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: $IMAGE_STREAM
  labels:
    app: $APP_NAME
EOF

echo "[INFO] Creating BuildConfig: $BUILD_CONFIG"
oc apply -f - <<EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: $BUILD_CONFIG
  labels:
    app: $APP_NAME
spec:
  output:
    to:
      kind: ImageStreamTag
      name: ${IMAGE_STREAM}:latest
  source:
    type: Binary
  strategy:
    type: Docker
  triggers:
    - type: ConfigChange
    - type: ImageChange
EOF

echo "[INFO] Starting build from local directory: $SRC_DIR"
oc start-build $BUILD_CONFIG --from-dir=$SRC_DIR --follow

echo "[INFO] Creating DeploymentConfig, Service, and Route"
cat <<EOF > $DEPLOYMENT_YAML
apiVersion: apps.openshift.io/v1
kind: DeploymentConfig
metadata:
  name: $APP_NAME
  labels:
    app: $APP_NAME
spec:
  replicas: 1
  selector:
    app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
        - name: tomcat
          image: image-registry.openshift-image-registry.svc:5000/${PROJECT}/${IMAGE_STREAM}:latest
          ports:
            - containerPort: 8080
  triggers:
    - type: ConfigChange
    - type: ImageChange
      imageChangeParams:
        automatic: true
        containerNames:
          - tomcat
        from:
          kind: ImageStreamTag
          name: ${IMAGE_STREAM}:latest
---
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  labels:
    app: $APP_NAME
spec:
  selector:
    app: $APP_NAME
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: $APP_NAME
spec:
  to:
    kind: Service
    name: $APP_NAME
  port:
    targetPort: 8080
  tls:
    termination: edge
EOF

oc apply -f $DEPLOYMENT_YAML

echo "[SUCCESS] Deployed: $APP_NAME"
oc get pods -l app=$APP_NAME
ROUTE=$(oc get route $APP_NAME -o jsonpath='{.spec.host}')
echo "App available at: http://$ROUTE"

