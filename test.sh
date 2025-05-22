#!/bin/bash

# === CONFIGURATION ===
TOKEN="your-openshift-token"
OPENSHIFT_API="https://your-openshift-api:6443"
PROJECT="myproject"
APP_NAME="my-tomcat-app"
IMAGE_NAME="${APP_NAME}-image"
CRYPTO_FILE_PATH="./properties/crypto.txt"

# === LOGIN WITH TOKEN ===
echo "🔐 Logging into OpenShift..."
oc login --token="$TOKEN" --server="$OPENSHIFT_API" --insecure-skip-tls-verify=true || {
  echo "❌ Login failed"; exit 1;
}

# === SELECT PROJECT ===
echo "🔄 Switching to project $PROJECT..."
oc project "$PROJECT" || {
  echo "❌ Failed to switch project"; exit 1;
}

# === CREATE OR UPDATE CONFIGMAP ===
echo "📦 Creating configmap from crypto.txt..."
oc create configmap crypto-config --from-file=crypto.txt="$CRYPTO_FILE_PATH" --dry-run=client -o yaml | oc apply -f - || {
  echo "❌ Failed to create configmap"; exit 1;
}

# === CREATE NEW BUILD CONFIG IF NOT EXISTS ===
if ! oc get bc/"$IMAGE_NAME" >/dev/null 2>&1; then
  echo "🛠 Creating new binary build config for $IMAGE_NAME..."
  oc new-build --name="$IMAGE_NAME" --binary --strategy=docker || {
    echo "❌ Failed to create new-build"; exit 1;
  }
else
  echo "✅ BuildConfig already exists"
fi

# === START BUILD ===
echo "📦 Starting build from current directory (Dockerfile + WAR)..."
oc start-build "$IMAGE_NAME" --from-dir=. --follow || {
  echo "❌ Build failed"; exit 1;
}

# === DEPLOYMENT YAML ===
echo "🚀 Deploying application..."

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
        image: ''
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
        name: ${IMAGE_NAME}:latest
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${APP_NAME}
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

# === ROLLOUT STATUS ===
echo "⏳ Waiting for deployment rollout..."
oc rollout status dc/${APP_NAME} || {
  echo "⚠️ Rollout failed or timeout"; exit 1;
}

# === DISPLAY ROUTE ===
ROUTE=$(oc get route ${APP_NAME} -o jsonpath='{.spec.host}')
echo "✅ Application is available at: http://${ROUTE}"
