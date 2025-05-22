apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-tomcat
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp-tomcat
  template:
    metadata:
      labels:
        app: myapp-tomcat
    spec:
      containers:
      - name: tomcat
        image: tomcat:9.0
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: myapp-tomcat
spec:
  selector:
    app: myapp-tomcat
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: myapp-tomcat
spec:
  to:
    kind: Service
    name: myapp-tomcat
  port:
    targetPort: 8080
  tls:
    termination: edge
