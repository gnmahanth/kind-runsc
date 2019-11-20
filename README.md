# kind-runsc
run runsc(gvisor) on kind clusters

- ### documents for reference 
    - installing gvisor(https://gvisor.dev/docs/user_guide/install/)
    - installing and using gvisor-containerd-shim-v2 (https://github.com/google/gvisor-containerd-shim/blob/master/docs/runtime-handler-shim-v2-quickstart.md)

- ### create docker image
    - kind node image donot come with runsc binary preinstalled, so we need to add it to image, here we are going to use kindest/node as base image and add runsc and containerd-shim-runsc-v1 to it

    ```Dockerfile
    FROM kindest/node:v1.15.6

    RUN echo "Installing gVisor binaries ..." \
        && export RUNSC_URL="https://storage.googleapis.com/gvisor/releases/nightly/latest/runsc" \
        && curl -sSL --retry 5 --output /usr/bin/runsc "${RUNSC_URL}" \
        && export RUNSC_SHIM_URL="https://github.com/google/gvisor-containerd-shim/releases/download/v0.0.3/containerd-shim-runsc-v1.linux-amd64"\
        && curl -sSL --retry 5 --output /usr/bin/containerd-shim-runsc-v1 "${RUNSC_SHIM_URL}"\
        && chmod 0755 /usr/bin/containerd-shim-runsc-v1 /usr/bin/runsc

    # copy updated containerd config 
    # uncomment/needed if kind version is < 0.6.0 
    # COPY config.toml /etc/containerd/config.toml
    ```
    - **only need if kind version is < 0.6.0**, update **/etc/containerd/config.toml** to use runsc and shim

    ```
    disabled_plugins = ["restart"]
    [plugins.linux]
    shim_debug = true
    [plugins.cri.containerd.runtimes.runsc]
    runtime_type = "io.containerd.runsc.v1"
    ```
    - create docker image with command 
    ```bash
    docker build . -t kindest/node-runsc:v1.15.6
    ```

- ### create kind cluster with new image kindest/node-runsc:v1.15.6 and cluster config
    - use kind.x-k8s.io/v1alpha4 and create cluster config file as below with name cluster.yaml
    ```yaml
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    containerdConfigPatches: 
    - |-
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
        runtime_type = "io.containerd.runsc.v1"
    ```
    - kind create cluster --config cluster.yaml --image kindest/node-runsc:v1.15.6

    ```bash
    $ kind version 
    kind v0.6.0 go1.13.4 linux/amd64
    $ kind create cluster --config runsc/cluster.yaml --image kindest/node-runsc:v1.15.6
    Creating cluster "kind" ...
    ✓ Ensuring node image (kindest/node-runsc:v1.15.6) 🖼
    ✓ Preparing nodes 📦 
    ✓ Writing configuration 📜 
    ✓ Starting control-plane 🕹️ 
    ✓ Installing CNI 🔌 
    ✓ Installing StorageClass 💾 
    Set kubectl context to "kind-kind"
    You can now use your cluster with:

    kubectl cluster-info --context kind-kind

    Have a question, bug, or feature request? Let us know! https://kind.sigs.k8s.io/#community 🙂
    ```

- ### check containerd config 
    ```bash
    $ docker exec -it kind-control-plane bash
    root@kind-control-plane:/# cat /etc/containerd/config.toml 
    version = 2

    [plugins]
      [plugins."io.containerd.grpc.v1.cri"]
        [plugins."io.containerd.grpc.v1.cri".containerd]
          [plugins."io.containerd.grpc.v1.cri".containerd.default_runtime]
            runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
            [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
              runtime_type = "io.containerd.runsc.v1"
            [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.test-handler]
              runtime_type = "io.containerd.runc.v2"
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
            ports:
            - containerPort: 80
    ```
    - check pod is runing
    ```bash
    $ kubectl get po 
    NAME                    READY   STATUS    RESTARTS   AGE
    nginx-889fdf958-sj4xh   1/1     Running   0          12m
    ```

    - verify nginx pod is runing on runsc
    ```bash
    $ docker exec -it kind-control-plane bash
    root@kind-control-plane:/# crictl ps -l
    CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID
    e2923953b220c       4152a96087525       19 seconds ago      Running             nginx               0                   76899735a7c97
    root@kind-control-plane:/# crictl exec  e2923953b220c dmesg 
    [    0.000000] Starting gVisor...
    [    0.526243] Feeding the init monster...
    [    0.592707] Creating bureaucratic processes...
    [    0.833332] Checking naughty and nice process list...
    [    1.000491] Letting the watchdogs out...
    [    1.232511] Committing treasure map to memory...
    [    1.707189] Segmenting fault lines...
    [    2.095068] Creating process schedule...
    [    2.210537] Mounting deweydecimalfs...
    [    2.510630] Creating cloned children...
    [    2.878071] Checking naughty and nice process list...
    [    3.213134] Ready!
    root@kind-control-plane:/# 
    ```