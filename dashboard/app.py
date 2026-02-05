"""
Sandbox Dashboard — control plane for Docker containers and DigitalOcean droplets.
"""

import json
import os
import subprocess
import re

import docker
import requests
import yaml
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

DOMAIN = os.environ.get("DOMAIN", "sandbox.example.com")
DO_TOKEN = os.environ.get("DO_TOKEN", "")
VPC_SUBNET = os.environ.get("VPC_SUBNET", "10.100.0.0/16")
SANDBOX_COMPOSE = "/opt/sandbox/sandbox/docker-compose.yml"
SANDBOX_DIR = "/opt/sandbox/sandbox"

DO_API = "https://api.digitalocean.com/v2"


def _do_headers():
    return {
        "Authorization": f"Bearer {DO_TOKEN}",
        "Content-Type": "application/json",
    }


def _docker_client():
    return docker.DockerClient(base_url="unix:///var/run/docker.sock")


# ── Pages ────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html", domain=DOMAIN)


# ── Container API ────────────────────────────────────────────────────

@app.route("/api/containers", methods=["GET"])
def list_containers():
    """List the 4 sandbox containers + any extras."""
    client = _docker_client()
    containers = client.containers.list(all=True, filters={"name": "sandbox-"})
    result = []
    for c in containers:
        result.append({
            "id": c.short_id,
            "name": c.name,
            "status": c.status,
            "image": c.image.tags[0] if c.image.tags else c.image.short_id,
            "labels": c.labels,
            "ip": _container_ip(c),
            "ports": _container_ports(c),
        })
    return jsonify(result)


@app.route("/api/containers/<name>/start", methods=["POST"])
def start_container(name):
    _validate_container_name(name)
    client = _docker_client()
    c = client.containers.get(name)
    c.start()
    return jsonify({"ok": True, "status": c.reload() or c.status})


@app.route("/api/containers/<name>/stop", methods=["POST"])
def stop_container(name):
    _validate_container_name(name)
    client = _docker_client()
    c = client.containers.get(name)
    c.stop(timeout=10)
    return jsonify({"ok": True, "status": "stopped"})


@app.route("/api/containers/<name>/restart", methods=["POST"])
def restart_container(name):
    _validate_container_name(name)
    client = _docker_client()
    c = client.containers.get(name)
    c.restart(timeout=10)
    return jsonify({"ok": True, "status": c.reload() or c.status})


@app.route("/api/containers/<name>/logs", methods=["GET"])
def container_logs(name):
    _validate_container_name(name)
    client = _docker_client()
    c = client.containers.get(name)
    tail = request.args.get("tail", "100")
    logs = c.logs(tail=int(tail), timestamps=True).decode("utf-8", errors="replace")
    return jsonify({"logs": logs})


@app.route("/api/containers/<name>/network", methods=["POST"])
def update_container_network(name):
    """
    Connect or disconnect a container from a network.
    Body: { "network": "sandbox_net", "action": "connect" | "disconnect" }
    """
    _validate_container_name(name)
    data = request.get_json(force=True)
    network_name = data.get("network", "sandbox_net")
    action = data.get("action", "connect")

    client = _docker_client()
    net = client.networks.get(network_name)
    container = client.containers.get(name)

    if action == "disconnect":
        net.disconnect(container)
    else:
        ip = data.get("ip")
        net.connect(container, ipv4_address=ip)

    return jsonify({"ok": True})


# ── Compose operations ───────────────────────────────────────────────

@app.route("/api/sandbox/up", methods=["POST"])
def sandbox_up():
    """Bring up the 4 sandbox containers."""
    result = subprocess.run(
        ["docker", "compose", "-f", SANDBOX_COMPOSE, "up", "-d"],
        capture_output=True, text=True, cwd=SANDBOX_DIR, timeout=120,
    )
    return jsonify({"ok": result.returncode == 0, "output": result.stdout + result.stderr})


@app.route("/api/sandbox/down", methods=["POST"])
def sandbox_down():
    """Tear down sandbox containers."""
    result = subprocess.run(
        ["docker", "compose", "-f", SANDBOX_COMPOSE, "down"],
        capture_output=True, text=True, cwd=SANDBOX_DIR, timeout=120,
    )
    return jsonify({"ok": result.returncode == 0, "output": result.stdout + result.stderr})


@app.route("/api/sandbox/config", methods=["GET"])
def sandbox_config():
    """Return current sandbox docker-compose.yml."""
    with open(SANDBOX_COMPOSE) as f:
        return jsonify(yaml.safe_load(f))


@app.route("/api/sandbox/config", methods=["PUT"])
def sandbox_update_config():
    """Update a container's image or settings in the compose file."""
    data = request.get_json(force=True)
    slot = data.get("slot")  # 1-4
    image = data.get("image")

    with open(SANDBOX_COMPOSE) as f:
        config = yaml.safe_load(f)

    svc_name = f"box{slot}"
    if svc_name in config.get("services", {}):
        if image:
            config["services"][svc_name]["image"] = image
        with open(SANDBOX_COMPOSE, "w") as f:
            yaml.dump(config, f, default_flow_style=False)
        return jsonify({"ok": True})

    return jsonify({"ok": False, "error": "Invalid slot"}), 400


# ── Droplet API ──────────────────────────────────────────────────────

@app.route("/api/droplets", methods=["GET"])
def list_droplets():
    """List all sandbox-tagged droplets via DO API."""
    resp = requests.get(
        f"{DO_API}/droplets?tag_name=sandbox",
        headers=_do_headers(),
        timeout=15,
    )
    resp.raise_for_status()
    droplets = resp.json().get("droplets", [])
    result = []
    for d in droplets:
        private_ip = ""
        public_ip = ""
        for net in d.get("networks", {}).get("v4", []):
            if net["type"] == "private":
                private_ip = net["ip_address"]
            elif net["type"] == "public":
                public_ip = net["ip_address"]
        result.append({
            "id": d["id"],
            "name": d["name"],
            "status": d["status"],
            "size": d["size_slug"],
            "region": d["region"]["slug"],
            "public_ip": public_ip,
            "private_ip": private_ip,
            "created_at": d["created_at"],
        })
    return jsonify(result)


@app.route("/api/droplets", methods=["POST"])
def create_droplet():
    """
    Spin up a new on-demand droplet in the sandbox VPC.
    Body: { "name": "myworker", "size": "s-1vcpu-1gb" }
    """
    data = request.get_json(force=True)
    name = data.get("name", "worker")
    size = data.get("size", "s-1vcpu-1gb")

    # Validate name
    if not re.match(r'^[a-z0-9][a-z0-9\-]{0,62}$', name):
        return jsonify({"ok": False, "error": "Invalid droplet name"}), 400

    # Get VPC and SSH key
    vpcs = requests.get(f"{DO_API}/vpcs", headers=_do_headers(), timeout=15).json()
    vpc_id = None
    for v in vpcs.get("vpcs", []):
        if v["name"] == "sandbox-vpc":
            vpc_id = v["id"]
            break

    keys = requests.get(f"{DO_API}/account/keys", headers=_do_headers(), timeout=15).json()
    key_ids = [k["id"] for k in keys.get("ssh_keys", [])]

    payload = {
        "name": f"sandbox-{name}",
        "region": "nyc1",
        "size": size,
        "image": "ubuntu-24-04-x64",
        "ssh_keys": key_ids,
        "vpc_uuid": vpc_id,
        "tags": ["sandbox", "worker"],
        "user_data": _worker_cloud_init(),
    }

    resp = requests.post(f"{DO_API}/droplets", headers=_do_headers(), json=payload, timeout=30)
    resp.raise_for_status()
    return jsonify({"ok": True, "droplet": resp.json().get("droplet", {})})


@app.route("/api/droplets/<int:droplet_id>", methods=["DELETE"])
def destroy_droplet(droplet_id):
    """Destroy an on-demand droplet."""
    resp = requests.delete(
        f"{DO_API}/droplets/{droplet_id}",
        headers=_do_headers(),
        timeout=15,
    )
    if resp.status_code == 204:
        return jsonify({"ok": True})
    return jsonify({"ok": False, "error": resp.text}), resp.status_code


# ── Networks API ─────────────────────────────────────────────────────

@app.route("/api/networks", methods=["GET"])
def list_networks():
    """List Docker networks."""
    client = _docker_client()
    nets = client.networks.list()
    result = []
    for n in nets:
        if n.name in ("bridge", "host", "none"):
            continue
        result.append({
            "id": n.short_id,
            "name": n.name,
            "driver": n.attrs.get("Driver"),
            "subnet": _network_subnet(n),
            "containers": [c.name for c in n.containers],
        })
    return jsonify(result)


# ── Helpers ──────────────────────────────────────────────────────────

def _validate_container_name(name):
    if not re.match(r'^sandbox-[a-z0-9\-]+$', name):
        from flask import abort
        abort(400, "Invalid container name")


def _container_ip(container):
    nets = container.attrs.get("NetworkSettings", {}).get("Networks", {})
    for net_name, net_info in nets.items():
        if net_info.get("IPAddress"):
            return net_info["IPAddress"]
    return ""


def _container_ports(container):
    port_map = container.attrs.get("NetworkSettings", {}).get("Ports", {}) or {}
    return {k: v for k, v in port_map.items() if v}


def _network_subnet(network):
    ipam = network.attrs.get("IPAM", {}).get("Config", [])
    if ipam:
        return ipam[0].get("Subnet", "")
    return ""


def _worker_cloud_init():
    return """#!/bin/bash
apt-get update && apt-get install -y docker.io docker-compose-v2 curl jq net-tools ufw
systemctl enable --now docker
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow from 10.100.0.0/16
ufw --force enable
echo ready > /opt/sandbox-status
"""


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
