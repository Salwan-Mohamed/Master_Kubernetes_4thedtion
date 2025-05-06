# Exercise 3: Implementing Kubernetes Design Patterns

This exercise explores key Kubernetes design patterns covered in Chapter 1, focusing on single-node patterns (sidecar, ambassador, adapter) and understanding multi-node patterns.

## Prerequisites

- Working Kubernetes cluster (minikube, kind, or cloud-based)
- kubectl CLI installed and configured
- Basic understanding of YAML manifests
- Familiarity with Kubernetes pod concepts

## Exercise Goals

- Implement and understand the Sidecar pattern
- Implement and understand the Ambassador pattern
- Implement and understand the Adapter pattern
- Explore declarative configuration and reconciliation loops

## Part 1: Sidecar Pattern Implementation

The sidecar pattern adds functionality to a main container by attaching a helper container in the same pod.

### 1. Create a Main Application with Logging Sidecar

Create a file called `sidecar-pattern.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-demo
  labels:
    app: sidecar-demo
spec:
  containers:
  - name: main-app
    image: nginx:latest
    ports:
    - containerPort: 80
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  - name: log-sidecar
    image: busybox:latest
    command: ["sh", "-c", "tail -f /var/log/nginx/access.log"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  volumes:
  - name: shared-logs
    emptyDir: {}
```

### 2. Deploy and Test the Sidecar Pattern

```bash
# Apply the manifest
kubectl apply -f sidecar-pattern.yaml

# Verify pods are running
kubectl get pods

# Generate logs by accessing the nginx app
kubectl port-forward sidecar-demo 8080:80 &
curl http://localhost:8080

# View the logs from the sidecar container
kubectl logs sidecar-demo -c log-sidecar
```

### 3. Extend the Sidecar Pattern

Enhance the sidecar to process logs by counting HTTP status codes. Create `enhanced-sidecar.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: enhanced-sidecar-demo
  labels:
    app: enhanced-sidecar-demo
spec:
  containers:
  - name: main-app
    image: nginx:latest
    ports:
    - containerPort: 80
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  - name: log-processor-sidecar
    image: busybox:latest
    command: ["/bin/sh", "-c"]
    args:
    - >
      while true; do
        echo "=== Log Statistics $(date) ===";
        grep -o "HTTP/1.1\" [0-9]*" /var/log/nginx/access.log | sort | uniq -c | sort -nr;
        sleep 10;
      done
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  volumes:
  - name: shared-logs
    emptyDir: {}
```

```bash
kubectl apply -f enhanced-sidecar.yaml
kubectl port-forward enhanced-sidecar-demo 8081:80 &
# Generate traffic with various status codes
curl http://localhost:8081
curl http://localhost:8081/nonexistent
kubectl logs enhanced-sidecar-demo -c log-processor-sidecar
```

## Part 2: Ambassador Pattern Implementation

The ambassador pattern presents a local proxy to a remote service.

### 1. Create a Simple Ambassador Pattern Pod

Create a file called `ambassador-pattern.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ambassador-demo
  labels:
    app: ambassador-demo
spec:
  containers:
  - name: main-app
    image: busybox:latest
    command: ["/bin/sh", "-c"]
    args:
    - >
      while true; do
        echo "Sending request to Redis via ambassador...";
        # Note: In a real app, you'd connect to redis directly,
        # but here we just connect to the ambassador on localhost
        wget -q -O- http://localhost:6379/GET/mykey || true;
        sleep 5;
      done
  - name: redis-ambassador
    image: hashicorp/http-echo:latest
    args:
      - "-text=SIMULATED REDIS RESPONSE: myvalue"
      - "-listen=:6379"
    ports:
      - containerPort: 6379
```

### 2. Deploy and Test the Ambassador Pattern

```bash
# Apply the manifest
kubectl apply -f ambassador-pattern.yaml

# Check that the pod is running
kubectl get pods

# View the logs from the main application
kubectl logs ambassador-demo -c main-app
```

### 3. Implement a More Realistic Ambassador

Create a file called `redis-ambassador.yaml` that simulates a more realistic Redis ambassador that could route to a primary for writes and replicas for reads:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: redis-ambassador-demo
  labels:
    app: redis-ambassador-demo
spec:
  containers:
  - name: web-app
    image: busybox:latest
    command: ["/bin/sh", "-c"]
    args:
    - >
      while true; do
        echo "=== READ operation via ambassador ===";
        wget -q -O- http://localhost:6379/read || true;
        sleep 2;
        echo "=== WRITE operation via ambassador ===";
        wget -q -O- http://localhost:6379/write || true;
        sleep 5;
      done
  - name: redis-ambassador
    image: python:3.9-alpine
    command: ["/bin/sh", "-c"]
    args:
    - >
      pip install flask &&
      cat > /app.py << 'EOF'
      from flask import Flask
      import time
      import random
      
      app = Flask(__name__)
      
      REDIS_MASTER = "redis-master.default.svc.cluster.local:6379"
      REDIS_REPLICAS = [
          "redis-replica-1.default.svc.cluster.local:6379",
          "redis-replica-2.default.svc.cluster.local:6379",
          "redis-replica-3.default.svc.cluster.local:6379"
      ]
      
      @app.route('/read')
      def read():
          # In a real ambassador, we'd route this to a random replica
          replica = random.choice(REDIS_REPLICAS)
          print(f"Routing READ request to replica: {replica}")
          # Simulate some latency
          time.sleep(0.1)
          return f"READ from {replica}: 'myvalue'"
      
      @app.route('/write')
      def write():
          # In a real ambassador, we'd route this to the master
          print(f"Routing WRITE request to master: {REDIS_MASTER}")
          # Simulate some latency
          time.sleep(0.1)
          return f"WRITE to {REDIS_MASTER}: 'OK'"
      
      if __name__ == "__main__":
          app.run(host="0.0.0.0", port=6379)
      EOF
      &&
      python /app.py
    ports:
    - containerPort: 6379
```

```bash
kubectl apply -f redis-ambassador.yaml
kubectl logs redis-ambassador-demo -c web-app
kubectl logs redis-ambassador-demo -c redis-ambassador
```

## Part 3: Adapter Pattern Implementation

The adapter pattern transforms the output of the main container into a standardized format.

### 1. Create a Simple Adapter Pattern Pod

Create a file called `adapter-pattern.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: adapter-demo
  labels:
    app: adapter-demo
spec:
  containers:
  - name: main-app
    image: busybox:latest
    command: ["/bin/sh", "-c"]
    args:
    - >
      while true; do
        # Generate non-standard log format
        echo "$(date +%s) - APP_LOG - User login: user123, status: success" >> /var/log/app/app.log;
        echo "$(date +%s) - APP_LOG - Page view: homepage, user: user123" >> /var/log/app/app.log;
        echo "$(date +%s) - APP_ERROR - Database connection timeout" >> /var/log/app/app.log;
        sleep 5;
      done
    volumeMounts:
    - name: app-logs
      mountPath: /var/log/app
  - name: log-adapter
    image: python:3.9-alpine
    command: ["/bin/sh", "-c"]
    args:
    - >
      pip install pyyaml &&
      cat > /adapter.py << 'EOF'
      import time
      import re
      import yaml
      import json
      
      log_pattern = re.compile(r'(\d+) - (\w+) - (.+)')
      
      def parse_log_line(line):
          match = log_pattern.match(line)
          if not match:
              return None
              
          timestamp, log_type, content = match.groups()
          
          # Convert to standardized JSON format
          log_entry = {
              "timestamp": int(timestamp),
              "datetime": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(timestamp))),
              "level": "ERROR" if log_type == "APP_ERROR" else "INFO",
              "message": content,
              "source": "custom-app"
          }
          
          # Additional parsing for specific log types
          if "User login" in content:
              username = re.search(r'User login: (\w+)', content).group(1)
              status = re.search(r'status: (\w+)', content).group(1)
              log_entry["event"] = "user_login"
              log_entry["username"] = username
              log_entry["status"] = status
          
          elif "Page view" in content:
              page = re.search(r'Page view: (\w+)', content).group(1)
              username = re.search(r'user: (\w+)', content).group(1)
              log_entry["event"] = "page_view"
              log_entry["page"] = page
              log_entry["username"] = username
          
          return log_entry
      
      # Monitor log file
      with open('/var/log/app/app.log', 'r') as log_file:
          # Go to the end of the file
          log_file.seek(0, 2)
          
          while True:
              line = log_file.readline().strip()
              if line:
                  log_entry = parse_log_line(line)
                  if log_entry:
                      # Output in both JSON and YAML formats for demonstration
                      print(f"JSON: {json.dumps(log_entry)}")
                      print(f"YAML: {yaml.dump(log_entry, default_flow_style=False)}")
              else:
                  time.sleep(0.1)
      EOF
      &&
      python /adapter.py
    volumeMounts:
    - name: app-logs
      mountPath: /var/log/app
  volumes:
  - name: app-logs
    emptyDir: {}
```

### 2. Deploy and Test the Adapter Pattern

```bash
# Apply the manifest
kubectl apply -f adapter-pattern.yaml

# Check that the pod is running
kubectl get pods

# Wait a moment for logs to be generated, then view the adapter output
kubectl logs adapter-demo -c log-adapter
```

## Part 4: Exploring Level-Triggered Architecture

Kubernetes uses a level-triggered architecture with declarative configuration. Let's explore this concept by creating and manipulating deployments.

### 1. Create a Deployment

Create a file called `level-triggered-demo.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: level-triggered-demo
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.14.2
        ports:
        - containerPort: 80
```

```bash
# Apply the deployment
kubectl apply -f level-triggered-demo.yaml

# Check the deployment
kubectl get deployments
kubectl get pods
```

### 2. Demonstrate Reconciliation

Now let's demonstrate Kubernetes' reconciliation by manually deleting a pod:

```bash
# Get the pod names
kubectl get pods -l app=nginx

# Delete one of the pods
POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $POD_NAME

# Watch Kubernetes recreate the pod
kubectl get pods -l app=nginx -w
```

### 3. Demonstrate Eventual Consistency

Edit the deployment to scale to 5 replicas:

```bash
kubectl edit deployment level-triggered-demo
# Change spec.replicas from 3 to 5, save and exit

# Watch as Kubernetes scales up
kubectl get pods -l app=nginx -w
```

### 4. Watch Kubernetes Reconciliation Events

```bash
kubectl get events --sort-by=.metadata.creationTimestamp | grep level-triggered-demo
```

### 5. Demonstrate Declarative Configuration

Let's update our deployment file to change both image version and replica count:

```bash
# Edit the deployment file
cat > level-triggered-demo-v2.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: level-triggered-demo
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.19.10
        ports:
        - containerPort: 80
EOF

# Apply the updated deployment
kubectl apply -f level-triggered-demo-v2.yaml

# Watch Kubernetes reconcile to the new desired state
kubectl get pods -l app=nginx -w

# Check the deployment details
kubectl describe deployment level-triggered-demo
```

## Part 5: Analysis and Reflection

After completing the hands-on explorations, consider these questions:

1. How does the sidecar pattern allow for separation of concerns in your application architecture?
2. What are some real-world use cases for the ambassador pattern in Kubernetes?
3. How does the adapter pattern help with migrating legacy applications to Kubernetes?
4. What are the advantages of Kubernetes' level-triggered architecture compared to edge-triggered systems?
5. How do these design patterns work together to form a comprehensive microservices architecture?

## Advanced Challenge: Combined Pattern Implementation

Design and implement a pod that combines all three single-node patterns (sidecar, ambassador, and adapter) working together:

1. A main application that generates content
2. A sidecar container that monitors the application
3. An ambassador container that provides an API gateway
4. An adapter container that transforms the output into a standard format

Document your implementation and explain how each component interacts with the others.

## Conclusion

Through this exercise, you've implemented and explored the fundamental Kubernetes design patterns that form the basis for microservices architecture in Kubernetes. These patterns provide powerful abstractions that enable separation of concerns, standardization, and adaptability in your containerized applications.