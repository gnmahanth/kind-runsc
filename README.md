# kind-runsc
run runsc(gvisor) on kind clusters

- ### documents for reference 
    - installing gvisor(https://gvisor.dev/docs/user_guide/install/)
    - installing and using gvisor-containerd-shim-v2 (https://github.com/google/gvisor-containerd-shim/blob/master/docs/runtime-handler-shim-v2-quickstart.md)

- ### create docker image
    - kind node image donot come with runsc binary preinstalled, so we need to add it to image, here we are going to use kindest/node as base image and add runsc and containerd-shim-runsc-v1 to it

    ```Dockerfile
    FROM kindest/node:v1.15.3

    RUN echo "Installing gVisor binaries ..." \
        && export RUNSC_URL="https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc" \
        && curl -sSL --retry 5 --output /usr/bin/runsc "${RUNSC_URL}" \
        && export RUNSC_SHIM_URL="https://github.com/google/gvisor-containerd-shim/releases/download/v0.0.3/containerd-shim-runsc-v1.linux-amd64"\
        && curl -sSL --retry 5 --output /usr/bin/containerd-shim-runsc-v1 "${RUNSC_SHIM_URL}"\
        && chmod 0755 /usr/bin/containerd-shim-runsc-v1 /usr/bin/runsc

    # copy updated containerd config 
    COPY config.toml /etc/containerd/config.toml
    ```
    - also update **/etc/containerd/config.toml** to use runsc and shim

    ```
    disabled_plugins = ["restart"]
    [plugins.linux]
    shim_debug = true
    [plugins.cri.containerd.runtimes.runsc]
    runtime_type = "io.containerd.runsc.v1"
    ```
    - create docker image with command 
    ```bash
    docker build . -t kindest/node-runsc:v1.15.3
    ```

- ### create kind cluster with new image **kindest/node-runsc:v1.15.3**
    - kind create cluster --image=kindest/node-runsc:v1.15.3

    ```bash
    $ kind create cluster --image=kindest/node-runsc:v1.15.3
    Creating cluster "kind" ...
    ✓ Ensuring node image (kindest/node-runsc:v1.15.3) 🖼 
    ✓ Preparing nodes 📦 
    ✓ Creating kubeadm config 📜 
    ✓ Starting control-plane 🕹️ 
    ✓ Installing CNI 🔌 
    ✓ Installing StorageClass 💾 
    Cluster creation complete. You can now use the cluster with:

    export KUBECONFIG="$(kind get kubeconfig-path --name="kind")"
    kubectl cluster-info
    ```

- ### using runsc
    - create runsc runtimeClass
    - runtime-class-runsc.yaml
    ```yaml
    ---
    kind: RuntimeClass
    apiVersion: node.k8s.io/v1beta1
    metadata:
      name: runsc 
    handler: runsc 
    ```

    ```bash
    $ kubectl apply -f runtime-class-runsc.yaml 
    runtimeclass.node.k8s.io/runsc created
    ```

    - create nginx deployment with **runtimeClassName: runsc** in template spec
    - nginx-runsc.yaml
    ```yaml
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      labels:
        app: nginx
      name: nginx
    spec:
      selector:
        matchLabels:
          app: nginx
      template:
        metadata:
          labels:
            app: nginx
        spec:
          runtimeClassName: runsc
          containers:
          - image: nginx
            name: nginx
    ```
    - check pod is runing
    ```bash
    $ kubectl get po
    NAME                    READY   STATUS    RESTARTS   AGE
    nginx-b595c98f9-fmm8c   1/1     Running   0          34m
    ```

    - verify nginx pod is runing on runsc
    ```bash
    $ docker exec -it kind-control-plane bash
    root@kind-control-plane:/# 
    root@kind-control-plane:/# crictl ps -l    
    CONTAINER ID   IMAGE          CREATED         STATE    NAME   ATTEMPT  POD ID
    8beaa8b0cb816  540a289bab6cb  26 minutes ago  Running  nginx  0        90e4fcd09a2ba
    root@kind-control-plane:/# 
    root@kind-control-plane:/# crictl exec  8beaa8b0cb816 dmesg 
    [    0.000000] Starting gVisor...
    [    0.205469] Digging up root...
    [    0.568020] Segmenting fault lines...
    [    1.023218] Rewriting operating system in Javascript...
    [    1.387699] Consulting tar man page...
    [    1.483042] Gathering forks...
    [    1.522388] Moving files to filing cabinet...
    [    1.938208] Letting the watchdogs out...
    [    2.004822] Creating bureaucratic processes...
    [    2.082958] Creating cloned children...
    [    2.131471] Reading process obituaries...
    [    2.387135] Ready!
    root@kind-control-plane:/# 
    ```