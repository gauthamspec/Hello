#!/bin/bash

# === CONFIGURATION ===
TOKEN="your-openshift-token"
OPENSHIFT_API="https://your-openshift-api:6443"
PROJECT="myproject"
APP_NAME="my-tomcat-app"
IMAGE_NAME="image-registry.openshift-image-registry.svc:5000/${PROJECT}/${APP_NAME}-image:latest"
CRYPTO_FILE_PATH="./properties/crypto.txt"  # Local path to crypto.txt

# === LOGIN USING TOKEN ===
echo "🔐 Logging into OpenShift with token..."
oc login --token="$TOKEN" --server="$OPENSHIFT_API" --insecure-skip-tls-verify=true || {
  echo "❌ Failed to log in with token"; exit 1;
}

# === SELECT PROJECT ===
echo "🔄 Switching to project: $PROJECT"
oc project "$PROJECT" || {
  echo "❌ Failed to switch to project $PROJECT"; exit 1;
}

# === CONFIGMAP ===
echo "📦 Creating ConfigMap from crypto.txt..."
oc create configmap crypto-config --from-file=crypto.txt="$CRYPTO_FILE_PATH" --dry-run=client -o yaml | oc apply -f - || {
  echo "❌ Failed to create or update configmap"; exit 1;
}

# === DEPLOYMENT CONFIG ===
echo "🚀 Applying DeploymentConfig, Service, and Route..."

cat <<EOF | oc apply -f -
apiVersion: apps.openshift.io/v1
kind: DeploymentConfig
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  replicas: 1
  selector:
    app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
      - name: tomcat
        image: ${IMAGE_NAME}
        imagePullPolicy: Always
        ports:
        - containerPort: 8080
        env:
        - name: CRYPTO_FILE_PATH
          value: "/usr/local/tomcat/properties/crypto.txt"
        - name: JAVA_OPTS
          value: "-Dcrypto.file.path=/usr/local/tomcat/properties/crypto.txt"
        volumeMounts:
        - name: crypto-volume
          mountPath: /usr/local/tomcat/properties/
      volumes:
      - name: crypto-volume
        configMap:
          name: crypto-config
  triggers:
  - type: ConfigChange
  - type: ImageChange
    imageChangeParams:
      automatic: true
      containerNames:
      - tomcat
      from:
        kind: ImageStreamTag
        name: ${APP_NAME}-image:latest
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  ports:
  - port: 8080
    targetPort: 8080
  selector:
    app: ${APP_NAME}
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  to:
    kind: Service
    name: ${APP_NAME}
  port:
    targetPort: 8080
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF

# === WAIT FOR ROLLOUT ===
echo "⏳ Waiting for deployment rollout..."
oc rollout status dc/${APP_NAME} || {
  echo "⚠️ Rollout failed or timed out"; exit 1;
}

# === GET ROUTE URL ===
ROUTE=$(oc get route ${APP_NAME} -o jsonpath='{.spec.host}')
if [ -n "$ROUTE" ]; then
  echo "✅ Application deployed and accessible at: http://${ROUTE}"
else
  echo "⚠️ Deployment succeeded but no route found"
fi
