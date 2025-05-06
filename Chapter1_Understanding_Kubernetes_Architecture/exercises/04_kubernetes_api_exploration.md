# Exercise 4: Exploring Kubernetes API and Resource Organization

This exercise takes a deep dive into the Kubernetes API, helping you understand how resources are organized and how to interact with the API directly.

## Prerequisites

- Working Kubernetes cluster (minikube, kind, or cloud-based)
- kubectl CLI installed and configured
- curl or similar HTTP client
- Basic understanding of REST APIs and JSON/YAML

## Exercise Goals

- Understand the Kubernetes API structure
- Learn to interact with the API directly
- Explore API groups and versioning
- Understand resource categories
- Create resources programmatically

## Part 1: Exploring the API Server

### 1. Access the Kubernetes API Server

First, let's set up a proxy to access the API:

```bash
# Start the kubectl proxy to access the API server
kubectl proxy --port=8080 &

# Check that the proxy is working
curl http://localhost:8080/api/
```

### 2. Navigate the API Structure

Let's explore the API structure:

```bash
# Get the available API groups
curl http://localhost:8080/apis/

# Explore the core API (v1)
curl http://localhost:8080/api/v1

# Look at a specific API group (apps)
curl http://localhost:8080/apis/apps/v1

# Get a list of deployments in the default namespace
curl http://localhost:8080/apis/apps/v1/namespaces/default/deployments
```

### 3. Get Detailed Information About API Resources

```bash
# Get information about all available resources
kubectl api-resources

# Get details about a specific resource (deployments)
kubectl explain deployment

# Get detailed field information
kubectl explain deployment.spec.template.spec.containers
```

## Part 2: Understanding API Versions and Groups

### 1. Explore API Versions

```bash
# List all API versions
kubectl api-versions

# Look at a specific version
kubectl api-resources --api-group=apps
```

### 2. Create a Simple Script to Map Resources to API Groups

Create a file called `api-explorer.sh`:

```bash
#!/bin/bash

echo "Kubernetes API Group Explorer"
echo "============================"

# Get all API groups
GROUPS=$(kubectl api-resources -o wide --sort-by=group | tail -n +2 | awk '{print $8}' | sort | uniq)

for GROUP in $GROUPS; do
  if [ -z "$GROUP" ]; then
    GROUP="core"
  fi
  
  echo -e "\nAPI Group: $GROUP"
  echo "----------------"
  kubectl api-resources -o wide --api-group=$GROUP | tail -n +2 | awk '{printf "%-30s %-10s %-40s\n", $1, $2, $3}'
done

echo -e "\nAPI Versions:"
echo "--------------"
kubectl api-versions | sort
```

Make it executable and run it:

```bash
chmod +x api-explorer.sh
./api-explorer.sh
```

## Part 3: Resource Categories and Organization

### 1. Create a Resource Category Map

Create a file called `resource-categories.py`:

```python
#!/usr/bin/env python3

import subprocess
import json
import yaml

# Define the resource categories
CATEGORIES = {
    "Workloads": [
        "deployment", "pod", "replicaset", "statefulset", "daemonset", "job", "cronjob"
    ],
    "Services & Networking": [
        "service", "ingress", "networkpolicy", "endpoints", "endpointslice"
    ],
    "Config & Storage": [
        "configmap", "secret", "persistentvolume", "persistentvolumeclaim", "storageclass"
    ],
    "RBAC": [
        "role", "rolebinding", "clusterrole", "clusterrolebinding", "serviceaccount"
    ],
    "Cluster": [
        "namespace", "node", "resourcequota", "limitrange", "podsecuritypolicy"
    ],
    "Metadata": [
        "customresourcedefinition", "event", "horizontalpodautoscaler", "poddisruptionbudget", 
        "priorityclass", "mutatingwebhookconfiguration", "validatingwebhookconfiguration"
    ]
}

# Get all resources as JSON
result = subprocess.run(
    ["kubectl", "api-resources", "-o", "wide", "--sort-by=name", "-o", "json"],
    capture_output=True,
    text=True
)

resources = json.loads(result.stdout)

# Initialize categorized resources
categorized = {category: [] for category in CATEGORIES}
uncategorized = []

# Categorize resources
for resource in resources["resources"]:
    name = resource["name"]
    categorized_flag = False
    
    for category, resource_list in CATEGORIES.items():
        if name in resource_list or any(name.endswith(f".{r}") for r in resource_list):
            categorized[category].append(resource)
            categorized_flag = True
            break
    
    if not categorized_flag:
        uncategorized.append(resource)

# Print the categorized resources
print("# Kubernetes Resource Categories\n")

for category, resources in categorized.items():
    print(f"## {category}\n")
    print("| Name | Kind | API Group | Namespaced |\n|------|------|-----------|------------|")
    
    for resource in sorted(resources, key=lambda r: r["name"]):
        name = resource["name"]
        kind = resource["kind"]
        group = resource["group"] if resource["group"] else "core"
        namespaced = "Yes" if resource["namespaced"] else "No"
        
        print(f"| {name} | {kind} | {group} | {namespaced} |")
    
    print()

print("## Uncategorized\n")
print("| Name | Kind | API Group | Namespaced |\n|------|------|-----------|------------|")
for resource in sorted(uncategorized, key=lambda r: r["name"]):
    name = resource["name"]
    kind = resource["kind"]
    group = resource["group"] if resource["group"] else "core"
    namespaced = "Yes" if resource["namespaced"] else "No"
    
    print(f"| {name} | {kind} | {group} | {namespaced} |")
```

Make it executable and run it:

```bash
chmod +x resource-categories.py
./resource-categories.py > kubernetes-resource-categories.md
```

### 2. Visualize Resource Relationships

Create a file called `resource-relationship.py`:

```python
#!/usr/bin/env python3

print("""
digraph G {
  rankdir=LR;
  node [shape=box, style=filled, fillcolor=lightblue];
  
  // Cluster-level resources
  subgraph cluster_0 {
    label = "Cluster Resources";
    style=filled;
    color=lightgrey;
    
    Node;
    Namespace;
    PersistentVolume;
    StorageClass;
    ClusterRole;
    ClusterRoleBinding;
  }
  
  // Namespace-level resources
  subgraph cluster_1 {
    label = "Namespace Resources";
    style=filled;
    color=lightgrey;
    
    // Workloads
    Deployment;
    StatefulSet;
    DaemonSet;
    ReplicaSet;
    Pod;
    Job;
    CronJob;
    
    // Services & Networking
    Service;
    Ingress;
    NetworkPolicy;
    
    // Config & Storage
    PersistentVolumeClaim;
    ConfigMap;
    Secret;
    
    // RBAC
    Role;
    RoleBinding;
    ServiceAccount;
  }
  
  // Relationships
  Namespace -> {Deployment StatefulSet DaemonSet Job CronJob Service Ingress NetworkPolicy PersistentVolumeClaim ConfigMap Secret Role RoleBinding ServiceAccount} [label="contains"];
  
  Deployment -> ReplicaSet [label="creates"];
  StatefulSet -> Pod [label="creates"];
  DaemonSet -> Pod [label="creates"];
  ReplicaSet -> Pod [label="creates"];
  Job -> Pod [label="creates"];
  CronJob -> Job [label="creates"];
  
  PersistentVolumeClaim -> PersistentVolume [label="binds"];
  StorageClass -> PersistentVolume [label="provisions"];
  
  Pod -> {ConfigMap Secret} [label="uses"];
  Pod -> PersistentVolumeClaim [label="mounts"];
  Pod -> ServiceAccount [label="uses"];
  
  Service -> Pod [label="selects"];
  Ingress -> Service [label="routes to"];
  
  Role -> RoleBinding [label="referenced by"];
  ClusterRole -> {RoleBinding ClusterRoleBinding} [label="referenced by"];
  ServiceAccount -> {RoleBinding ClusterRoleBinding} [label="bound by"];
  
  Node -> Pod [label="hosts"];
}
""")
```

Run it to generate a DOT file that can be visualized with GraphViz:

```bash
chmod +x resource-relationship.py
./resource-relationship.py > kubernetes-resources.dot

# If you have GraphViz installed, generate an image:
dot -Tpng kubernetes-resources.dot -o kubernetes-resources.png
```

## Part 4: Working with the API Programmatically

### 1. Create a Pod with a Direct API Call

Create a file called `create-pod-api.sh`:

```bash
#!/bin/bash

# Define the pod manifest
cat > api-demo-pod.json << EOF
{
  "apiVersion": "v1",
  "kind": "Pod",
  "metadata": {
    "name": "api-demo-pod",
    "labels": {
      "app": "api-demo"
    }
  },
  "spec": {
    "containers": [
      {
        "name": "nginx",
        "image": "nginx:latest",
        "ports": [
          {
            "containerPort": 80
          }
        ]
      }
    ]
  }
}
EOF

# Use kubectl proxy for authentication
kubectl proxy --port=8080 &
PROXY_PID=$!

# Wait for the proxy to start
sleep 2

# Create the pod using the API
curl -X POST -H "Content-Type: application/json" \
  -d @api-demo-pod.json \
  http://localhost:8080/api/v1/namespaces/default/pods

# Clean up
kill $PROXY_PID
```

Make it executable and run it:

```bash
chmod +x create-pod-api.sh
./create-pod-api.sh

# Verify the pod was created
kubectl get pods api-demo-pod
```

### 2. Watch Resources with the API

Create a file called `watch-pods.py`:

```python
#!/usr/bin/env python3

import subprocess
import json
import time
import sys

def watch_pods():
    # Start the kubectl proxy
    proxy_process = subprocess.Popen(["kubectl", "proxy", "--port=8080"], stderr=subprocess.PIPE)
    
    # Wait for the proxy to start
    time.sleep(2)
    
    try:
        print("Watching pods in the default namespace...")
        print("Press Ctrl+C to stop watching.")
        print("-" * 80)
        
        # Get the initial state
        process = subprocess.run(
            ["curl", "-s", "http://localhost:8080/api/v1/namespaces/default/pods"],
            capture_output=True,
            text=True
        )
        
        pods_data = json.loads(process.stdout)
        current_pods = {pod["metadata"]["name"]: pod["status"]["phase"] for pod in pods_data["items"]}
        
        # Print initial state
        print(f"Initial state - {len(current_pods)} pods:")
        for name, phase in current_pods.items():
            print(f"  - {name}: {phase}")
        
        # Watch for changes
        while True:
            time.sleep(2)
            
            process = subprocess.run(
                ["curl", "-s", "http://localhost:8080/api/v1/namespaces/default/pods"],
                capture_output=True,
                text=True
            )
            
            pods_data = json.loads(process.stdout)
            new_pods = {pod["metadata"]["name"]: pod["status"]["phase"] for pod in pods_data["items"]}
            
            # Check for added pods
            for name, phase in new_pods.items():
                if name not in current_pods:
                    print(f"POD ADDED: {name} ({phase})")
                elif current_pods[name] != phase:
                    print(f"POD UPDATED: {name} ({current_pods[name]} -> {phase})")
            
            # Check for removed pods
            for name in current_pods:
                if name not in new_pods:
                    print(f"POD DELETED: {name}")
            
            # Update current state
            current_pods = new_pods
    
    except KeyboardInterrupt:
        print("\nStopping pod watcher...")
    finally:
        # Clean up
        proxy_process.terminate()

if __name__ == "__main__":
    watch_pods()
```

Make it executable and run it:

```bash
chmod +x watch-pods.py
./watch-pods.py

# Open a second terminal and create/delete pods to see changes
```

## Part 5: Understanding Custom Resources

### 1. Create a Simple Custom Resource Definition

Create a file called `microservice-crd.yaml`:

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: microservices.example.com
spec:
  group: example.com
  names:
    kind: Microservice
    listKind: MicroserviceList
    plural: microservices
    singular: microservice
    shortNames:
      - ms
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                replicas:
                  type: integer
                  minimum: 1
                  default: 1
                image:
                  type: string
                port:
                  type: integer
                  minimum: 1
                  maximum: 65535
                env:
                  type: array
                  items:
                    type: object
                    required:
                      - name
                    properties:
                      name:
                        type: string
                      value:
                        type: string
              required:
                - image
                - port
```

Apply the CRD:

```bash
kubectl apply -f microservice-crd.yaml

# Verify the CRD was created
kubectl get crd microservices.example.com
```

### 2. Create a Microservice Instance

Create a file called `example-microservice.yaml`:

```yaml
apiVersion: example.com/v1
kind: Microservice
metadata:
  name: example-service
spec:
  replicas: 3
  image: nginx:latest
  port: 80
  env:
    - name: ENVIRONMENT
      value: development
    - name: LOG_LEVEL
      value: debug
```

Apply the Microservice:

```bash
kubectl apply -f example-microservice.yaml

# Check that the microservice was created
kubectl get microservices
kubectl get ms # Using the short name
kubectl describe microservice example-service
```

## Part 6: Analysis and Reflection

After completing the hands-on explorations, consider these questions:

1. How does the Kubernetes API organization contribute to the platform's extensibility?
2. What are the advantages of having different API groups and versions?
3. How does the resource categorization help in understanding Kubernetes architecture?
4. What benefits do Custom Resource Definitions provide to Kubernetes users?
5. How would you use the Kubernetes API directly in a DevOps automation pipeline?

## Advanced Challenge

Design and implement a simple Kubernetes client that:

1. Connects to the Kubernetes API
2. Lists resources from different API groups
3. Creates and monitors a deployment
4. Watches for changes and reacts accordingly

You can use any programming language (Python, Go, JavaScript, etc.) for this task.

Create a file called `simple-k8s-client.py`:

```python
#!/usr/bin/env python3

import requests
import json
import subprocess
import time
import argparse
import sys
import os

class KubernetesClient:
    def __init__(self, proxy_port=8080):
        self.proxy_port = proxy_port
        self.base_url = f"http://localhost:{proxy_port}"
        self.proxy_process = None
        
    def start_proxy(self):
        """Start the kubectl proxy to access the API server."""
        print("Starting kubectl proxy...")
        self.proxy_process = subprocess.Popen(
            ["kubectl", "proxy", f"--port={self.proxy_port}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        time.sleep(2)  # Wait for proxy to start
        
    def stop_proxy(self):
        """Stop the kubectl proxy."""
        if self.proxy_process:
            print("Stopping kubectl proxy...")
            self.proxy_process.terminate()
            
    def get_api_resources(self):
        """Get all API resources grouped by API group."""
        print("Fetching API resources...")
        
        # Get API groups
        response = requests.get(f"{self.base_url}/apis")
        groups_data = response.json()
        
        # Process core API (v1)
        response = requests.get(f"{self.base_url}/api/v1")
        core_data = response.json()
        
        result = {
            "core": {
                "version": "v1",
                "resources": [res["name"] for res in core_data["resources"]]
            }
        }
        
        # Process other API groups
        for group in groups_data["groups"]:
            group_name = group["name"]
            preferred_version = next((v for v in group["versions"] if v.get("groupVersion") == group.get("preferredVersion", {}).get("groupVersion")), group["versions"][0])
            version_name = preferred_version["version"]
            
            response = requests.get(f"{self.base_url}/apis/{group_name}/{version_name}")
            if response.status_code == 200:
                group_data = response.json()
                result[group_name] = {
                    "version": version_name,
                    "resources": [res["name"] for res in group_data.get("resources", [])]
                }
        
        return result
        
    def create_deployment(self, name, image, replicas=1, namespace="default"):
        """Create a deployment."""
        print(f"Creating deployment {name} with image {image}...")
        
        deployment = {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "metadata": {
                "name": name,
                "namespace": namespace
            },
            "spec": {
                "replicas": replicas,
                "selector": {
                    "matchLabels": {
                        "app": name
                    }
                },
                "template": {
                    "metadata": {
                        "labels": {
                            "app": name
                        }
                    },
                    "spec": {
                        "containers": [
                            {
                                "name": name,
                                "image": image,
                                "ports": [
                                    {
                                        "containerPort": 80
                                    }
                                ]
                            }
                        ]
                    }
                }
            }
        }
        
        response = requests.post(
            f"{self.base_url}/apis/apps/v1/namespaces/{namespace}/deployments",
            json=deployment,
            headers={"Content-Type": "application/json"}
        )
        
        if response.status_code in (200, 201, 202):
            print(f"Deployment {name} created successfully!")
            return response.json()
        else:
            print(f"Failed to create deployment: {response.status_code} {response.text}")
            return None
    
    def watch_deployment(self, name, namespace="default", timeout=60):
        """Watch a deployment until it's ready or timeout."""
        print(f"Watching deployment {name}...")
        
        start_time = time.time()
        while time.time() - start_time < timeout:
            response = requests.get(
                f"{self.base_url}/apis/apps/v1/namespaces/{namespace}/deployments/{name}"
            )
            
            if response.status_code == 200:
                deployment_data = response.json()
                
                available_replicas = deployment_data["status"].get("availableReplicas", 0)
                desired_replicas = deployment_data["spec"]["replicas"]
                
                print(f"Status: {available_replicas}/{desired_replicas} replicas available")
                
                if available_replicas == desired_replicas:
                    print(f"Deployment {name} is ready!")
                    return True
            
            time.sleep(3)
        
        print(f"Timed out waiting for deployment {name} to be ready")
        return False

    def list_pods(self, namespace="default", label_selector=None):
        """List pods in a namespace."""
        url = f"{self.base_url}/api/v1/namespaces/{namespace}/pods"
        if label_selector:
            url += f"?labelSelector={label_selector}"
            
        response = requests.get(url)
        
        if response.status_code == 200:
            return response.json()["items"]
        else:
            print(f"Failed to list pods: {response.status_code} {response.text}")
            return []

def main():
    parser = argparse.ArgumentParser(description="Simple Kubernetes Client")
    parser.add_argument("--port", type=int, default=8080, help="Port for kubectl proxy")
    parser.add_argument("command", choices=["list-apis", "create-deployment", "watch"])
    parser.add_argument("--name", help="Name for deployment")
    parser.add_argument("--image", help="Image for deployment")
    parser.add_argument("--replicas", type=int, default=1, help="Number of replicas")
    parser.add_argument("--namespace", default="default", help="Kubernetes namespace")
    
    args = parser.parse_args()
    
    client = KubernetesClient(proxy_port=args.port)
    
    try:
        client.start_proxy()
        
        if args.command == "list-apis":
            api_resources = client.get_api_resources()
            print("\nAPI Groups and Resources:")
            print("========================")
            
            for group_name, group_data in api_resources.items():
                print(f"\n{group_name} ({group_data['version']}):")
                print("-" * 40)
                for resource in sorted(group_data["resources"]):
                    print(f"  - {resource}")
                    
        elif args.command == "create-deployment":
            if not args.name or not args.image:
                print("Error: --name and --image are required for create-deployment")
                sys.exit(1)
                
            client.create_deployment(
                name=args.name,
                image=args.image,
                replicas=args.replicas,
                namespace=args.namespace
            )
            
        elif args.command == "watch":
            if not args.name:
                print("Error: --name is required for watch")
                sys.exit(1)
                
            client.watch_deployment(
                name=args.name,
                namespace=args.namespace
            )
            
            print("\nPods created by the deployment:")
            pods = client.list_pods(
                namespace=args.namespace,
                label_selector=f"app={args.name}"
            )
            
            for pod in pods:
                status = pod["status"]["phase"]
                node = pod["spec"].get("nodeName", "unknown")
                print(f"  - {pod['metadata']['name']} ({status}) on node {node}")
    
    finally:
        client.stop_proxy()

if __name__ == "__main__":
    main()
```

Make the script executable and try it out:

```bash
chmod +x simple-k8s-client.py

# List API resources
./simple-k8s-client.py list-apis

# Create a deployment
./simple-k8s-client.py create-deployment --name nginx-demo --image nginx:latest --replicas 3

# Watch the deployment
./simple-k8s-client.py watch --name nginx-demo
```

## Conclusion

Through this exercise, you've gained a deeper understanding of the Kubernetes API architecture, how resources are organized, and how to interact with the API programmatically. This knowledge is essential for advanced Kubernetes operations, custom controller development, and building automation tools.

The Kubernetes API's design with its version-based grouping mechanism, declarative configuration approach, and extensibility through custom resources provides a solid foundation for building complex containerized applications while maintaining backward compatibility and enabling future growth.

Understanding the API at this level prepares you for exploring more advanced Kubernetes topics like custom controllers, operators, and admission webhooks in subsequent chapters.
