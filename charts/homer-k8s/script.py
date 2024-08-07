#!/usr/bin/env python

from kubernetes import client, config
from PIL import Image
from urllib.parse import urlparse

import favicon
import os
import pdb
import requests
import time
import yaml

config.load_incluster_config()

# Default icon if no favicon exists on site
DEFAULT_ICON = os.getenv('HOMERK8S_DEFAULT_ICON', "/www/assets/icons/favicon-32x32.png")
# Default sleep interval between updates, 0 for one-shot
SLEEP_INTERVAL = int(os.getenv('HOMERK8S_SLEEP_INTERVAL', 60))

homer_page = {
  "title": "Dashboard",
  "subtitle": "Generated from K8s nginx-ingress",
  "logo": "Generated from K8s nginx-ingress",
  "header": True,
  "footer": False,
  "links": [],
  "services": [
    {
    "name": "nginx-ingress",
    "icon": "fas fa-server",
    "items": []
    }
  ],
}

def get_fav_icon(url, download_location):
  retval = None
  if not os.path.isdir(download_location):
    os.makedirs(download_location)

  icons = favicon.get(url)
  if len(icons) == 0:
    return DEFAULT_ICON

  icon = favicon.get(url)[0]
  response = requests.get(icon.url, stream=True, verify=False)
  response.raise_for_status()

  urlparts = urlparse(url)
  target_file = "%s/%s-favicon.%s" % (download_location,
                                      urlparts.netloc,
                                      icon.format)
  with open(target_file, 'wb') as image:
    for chunk in response.iter_content(1024):
      image.write(chunk)
    retval = target_file
  return retval

def download_fav_icon(namespace, service_name, download_location, url):
  fav_icon = None

  eps_api = client.CoreV1Api()
  eps = eps_api.list_namespaced_endpoints(\
          namespace=namespace,
          field_selector='metadata.name=%s' % service_name)
  for ep in eps.items:
    if ep.subsets and ep.subsets[0].addresses:
      pod_ip = ep.subsets[0].addresses[0].ip
      pod_port = ep.subsets[0].ports[0].port
      try:
        # Try public URL
        fav_icon = get_fav_icon(url, download_location)
        return fav_icon
      except Exception as ex:
        try:
          # Try K8s endpoint with http
          fav_icon = get_fav_icon('http://%s:%s' % (pod_ip, pod_port), download_location)
          return fav_icon
        except Exception as ex:
          try:
            # Try K8s endpoint with https
            fav_icon = get_fav_icon('https://%s:%s' % (pod_ip, pod_port), download_location)
            return fav_icon
          except Exception as ex:
            print("Unable to get fav_icon via public URL or "
                  "http/https K8s endpoints: %s: %s" % (url, ex))
            return ex
  return fav_icon

networking_v1_beta1_api = client.NetworkingV1beta1Api()

while True:
  homer_page['services'][0]['items'] = []
  ingresses = networking_v1_beta1_api.list_ingress_for_all_namespaces()
  for ingress in ingresses.items:
    print(ingress.spec.rules[0].host)
    url = "https://%s" % ingress.spec.rules[0].host
    urlparts = urlparse(url)
    fav_icon = download_fav_icon(\
        ingress.metadata.namespace,
        ingress.spec.rules[0].http.paths[0].backend.service_name,
        "/www/assets/favicons",
        url)
    service = {"name": urlparts.netloc,
               "url": url,
               "target": "_blank"}
    if fav_icon:
      if isinstance(fav_icon, Exception):
        # ingress has endpoints, but received an exception
        service['subtitle'] = "Error: %s" % (fav_icon)
      else:
        try:
          if Image.open(fav_icon):
            # ingress / ep are good to go
            service['logo'] = fav_icon.replace('/www/assets', 'assets')
        except Exception as ex:
          print("Invalid image: %s" % fav_icon)
          service['logo'] = DEFAULT_ICON.replace('/www/assets', 'assets')
    else:
      # ingress has no endpoints
      service['subtitle'] = "Error: No endpoints for K8s svc behind ingress"

    homer_page['services'][0]['items'].append(service)

  k8s_fav_icon = get_fav_icon('https://kubernetes.io/', '/www/assets/favicons')
  if k8s_fav_icon:
    homer_page['logo'] = k8s_fav_icon.replace('/www/assets', 'assets')

  with open("/www/assets/config.yml", "w+") as outfile:
    outfile.write(yaml.dump(homer_page, default_flow_style=False))

  if SLEEP_INTERVAL <= 0:
    break

  print()
  print("Sleeping for %s seconds..." % SLEEP_INTERVAL)
  for i in range(SLEEP_INTERVAL):
    time.sleep(1)
