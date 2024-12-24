#!/usr/bin/env python3

import os
import json
import time
import logging
import http.client
import urllib.parse
import ssl
import subprocess
from datetime import datetime, timedelta

SECRETS_FILE_PATH = os.path.join(os.path.dirname(__file__), '../../config/secrets.ejson')

OMADA_CONTROLLER_IP = "192.168.0.110"
OMADA_CONTROLLER_PORT = 443
OMADA_BASE_URL = f"https://{OMADA_CONTROLLER_IP}:{OMADA_CONTROLLER_PORT}"
OMADA_SITE_NAME = "Default"

TECHNITIUM_DNS_IP = "192.168.50.100"
TECHNITUM_DNS_PORT = 5380
TECHNITIUM_ADD_RECORDS_URL = f"http://{TECHNITIUM_DNS_IP}:{TECHNITUM_DNS_PORT}/api/zones/records/add"
TECHNITIUM_UPDATE_RECORDS_URL = f"http://{TECHNITIUM_DNS_IP}:{TECHNITUM_DNS_PORT}/api/zones/records/update"
TECHNITIUM_GET_RECORDS_URL = f"http://{TECHNITIUM_DNS_IP}:{TECHNITUM_DNS_PORT}/api/zones/records/get"
TECHNITIUM_DELETE_RECORDS_URL = f"http://{TECHNITIUM_DNS_IP}:{TECHNITUM_DNS_PORT}/api/zones/records/delete"
TECHNITIUM_DELETE_DNS_CACHE_URL = f"http://{TECHNITIUM_DNS_IP}:{TECHNITUM_DNS_PORT}/api/cache/delete"

DEFAULT_ZONE = "home.arpa"
LAB_ZONE = "lab.home.arpa"

LAB_HOSTNAMES = ["collie", "terrier", "retriever", "shepherd", "games1"]

CUSTOM_DNS_FILE = os.path.join(os.path.dirname(__file__), '../../config/custom_dns.json')

def main():
  if not os.path.isfile(SECRETS_FILE_PATH):
    raise FileNotFoundError(f"Secrets file not found at {SECRETS_FILE_PATH}")

  secrets = decrypt_ejson(SECRETS_FILE_PATH)

  omada_id = secrets["omada_id"]
  client_id = secrets["omada_client_id"]
  client_secret = secrets["omada_client_secret"]
  technitium_token = secrets["technitium_dns_access_token"]

  custom_dns = {}
  if os.path.isfile(CUSTOM_DNS_FILE):

    with open(CUSTOM_DNS_FILE, "r") as f:
      custom_dns = json.load(f)

  logger = setup_logger()
  logger.info("Starting DNS records update process.")

  omada_access_token, omada_token_expiry = get_access_token(logger, omada_id, client_id, client_secret)
  if omada_access_token is None:
    logger.error("Failed to acquire access token.")
    return

  omada_devices = get_omada_devices(logger, omada_id, omada_access_token, omada_token_expiry)
  if not omada_devices:
    logger.error("Failed to acquire devices.")
    return

  logger.info(f"Omada devices acquired successfully. Found {len(omada_devices)} devices.")

  err = update_dns_records(logger, technitium_token, omada_devices, custom_dns)
  if err:
    logger.error(f"Failed to update DNS records. Err: {err}")
    return
  logger.info("DNS records updated successfully.")

  if clear_dns_cache(logger, technitium_token):
    logger.error("Failed to clear DNS cache.")
    return
  logger.info("DNS cache cleared successfully.")

def setup_logger():
  logger = logging.getLogger()
  logger.setLevel(logging.DEBUG)
  handler = logging.StreamHandler()
  formatter = logging.Formatter('%(asctime)s %(levelname)s: %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
  handler.setFormatter(formatter)
  logger.addHandler(handler)
  return logger

def decrypt_ejson(file_path):
  result = subprocess.run(['ejson', 'decrypt', file_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
  if result.returncode != 0:
    raise RuntimeError(f"Failed to decrypt {file_path}: {result.stderr}")
  return json.loads(result.stdout)

def get_access_token(logger, omada_id, client_id, client_secret):
  url = f"{OMADA_BASE_URL}/openapi/authorize/token?grant_type=client_credentials"
  headers = {"Content-Type": "application/json"}
  data = json.dumps({"omadacId": omada_id, "client_id": client_id, "client_secret": client_secret})

  parsed_url = urllib.parse.urlparse(url)
  conn = http.client.HTTPSConnection(parsed_url.hostname, parsed_url.port, context=ssl._create_unverified_context())
  conn.request("POST", parsed_url.path + "?" + parsed_url.query, body=data, headers=headers)
  response = conn.getresponse()
  response_data = json.loads(response.read().decode())

  if response_data.get("errorCode") == 0:
    access_token = response_data["result"]["accessToken"]
    expires_in = response_data["result"]["expiresIn"]
    token_expiry = datetime.now() + timedelta(seconds=expires_in)
    logger.info("Access token acquired successfully.")
    return access_token, token_expiry
  else:
    logger.error("Failed to acquire access token.")
    return None, None

def token_expired(token_expiry):
  return token_expiry is None or datetime.now() > token_expiry

def get_site_id(logger, omada_id, access_token, token_expiry):
  if token_expired(token_expiry):
    access_token, token_expiry = get_access_token(logger, omada_id, client_id, client_secret)

  headers = {"Authorization": f"AccessToken={access_token}"}
  sites_url = f"{OMADA_BASE_URL}/openapi/v1/{omada_id}/sites?page=1&pageSize=100"
  parsed_url = urllib.parse.urlparse(sites_url)
  conn = http.client.HTTPSConnection(parsed_url.hostname, parsed_url.port, context=ssl._create_unverified_context())
  conn.request("GET", parsed_url.path + "?" + parsed_url.query, headers=headers)
  response = conn.getresponse()
  response_data = json.loads(response.read().decode())

  if response_data.get("errorCode") != 0:
    logger.error("failed to acquire site id, response: %s", response_data)
    return None

  sites = response_data["result"]["data"]
  for site in sites:
    if site["name"] == OMADA_SITE_NAME:
      logger.info("Site id acquired successfully.")
      return site["siteId"]

  return None


def get_omada_devices(logger, omada_id, access_token, token_expiry):
  if token_expired(token_expiry):
    access_token, token_expiry = get_access_token(logger, omada_id, client_id, client_secret)

  site_id = get_site_id(logger, omada_id, access_token, token_expiry)
  if site_id is None:
    logger.error("Failed to acquire site id.")
    return {}

  headers = {"Authorization": f"AccessToken={access_token}"}
  current_page = 1
  page_size = 100
  total_devices = -1
  devices_count = 0

  device_info = {}

  while True:
    devices_url = f"{OMADA_BASE_URL}/openapi/v1/{omada_id}/sites/{site_id}/clients?page={current_page}&pageSize={page_size}"
    parsed_url = urllib.parse.urlparse(devices_url)
    conn = http.client.HTTPSConnection(parsed_url.hostname, parsed_url.port, context=ssl._create_unverified_context())
    conn.request("GET", parsed_url.path + "?" + parsed_url.query, headers=headers)
    response = conn.getresponse()
    response_data = json.loads(response.read().decode())

    print(devices_url)
    print(headers)

    if response_data.get("errorCode") != 0:
      logger.error("failed to acquire devices, response: %s", response_data)
      return {}

    result = response_data["result"]
    if total_devices < 0:
      total_devices = result["totalRows"]

    devices_count = min(devices_count + page_size, total_devices)
    devices = result["data"]

    for device in devices:
      if "name" not in device or "ip" not in device:
        continue

      hostname = device["name"]
      record_value = device["ip"]
      if hostname and record_value:
        device_info[hostname.lower().replace("_", "-").replace(" ", "-").replace(".", "-")] = record_value

    if devices_count >= total_devices:
      break

    current_page += 1

  return device_info

def update_dns_records(logger, technitium_token, omada_devices, custom_dns):
  unsuccessful_records = []
  for hostname, record_value in omada_devices.items():
    domain = f"{hostname}.{DEFAULT_ZONE}"
    if hostname in LAB_HOSTNAMES:
      domain = f"{hostname}.{LAB_ZONE}"

    logger.info(f"Gathering DNS records for {hostname} ({record_value})")
    dns_records = get_dns_record(logger, technitium_token, domain)

    if len(dns_records) == 0:
      logger.info(f"No DNS records found for {hostname} ({record_value}), so adding one.")
      if not add_dns_record(logger, technitium_token, domain, record_value):
        unsuccessful_records.append(f"{hostname} ({record_value})")
    elif len(dns_records) == 1:
      logger.info(f"DNS record found for {hostname} ({record_value}), so updating it with new IP address.")
      current_record_value = get_current_value_from_dns_records(dns_records[0])
      if current_record_value != record_value and not update_dns_record(logger, technitium_token, domain, current_record_value, record_value):
        unsuccessful_records.append(f"{hostname} ({record_value})")
    else:
      logger.info(f"Multiple DNS records found for {hostname} ({record_value}), so deleting all and adding new one.")
      for dns_record in dns_records:
        delete_dns_record(logger, technitium_token, domain, get_current_value_from_dns_records(dns_record))

      if not add_dns_record(logger, technitium_token, domain, record_value):
        unsuccessful_records.append(f"{hostname} ({record_value})")

  logger.info("Device DNS records updated successfully.")
  logger.info("...")

  # Add custom DNS records
  logger.info(f"Adding {len(custom_dns)} custom DNS records.")
  for record in custom_dns:
    fqdn = record["fqdn"]
    record_type = record["type"]
    value = record["value"]

    existing_record = get_dns_record(logger, technitium_token, fqdn)
    if len(existing_record) == 0:
      logger.info(f"No DNS records found for {fqdn}, so adding one.")
      if not add_dns_record(logger, technitium_token, fqdn, value, record_type):
        unsuccessful_records.append(f"{fqdn} ({value})")
    elif len(existing_record) == 1:
      logger.info(f"DNS record found for {fqdn}, so updating it with new value.")

      current_value = get_current_value_from_dns_records(existing_record[0], record_type)
      if current_value != value and not update_dns_record(logger, technitium_token, fqdn, current_value, value, record_type):
        unsuccessful_records.append(f"{fqdn} ({value})")
    else:
      logger.info(f"Multiple DNS records found for {fqdn}, so deleting all and adding new one.")
      for dns_record in existing_record:
        record_value = get_current_value_from_dns_records(dns_record, record_type)
        delete_dns_record(logger, technitium_token, fqdn, record_value, record_type)

      if not add_dns_record(logger, technitium_token, fqdn, value, record_type):
        unsuccessful_records.append(f"{fqdn} ({value})")

  logger.info("Custom DNS records added successfully.")
  return "Failed to update records: " + ", ".join(unsuccessful_records) if unsuccessful_records else None

def get_current_value_from_dns_records(dns_record, record_type="A"):
  if record_type == "CNAME":
    return dns_record["rData"]["cname"]

  return dns_record["rData"]["ipAddress"]

def get_dns_record(logger, technitium_token, domain):
  url = f"{TECHNITIUM_GET_RECORDS_URL}?token={technitium_token}&domain={domain}"
  parsed_url = urllib.parse.urlparse(url)
  conn = http.client.HTTPConnection(parsed_url.hostname, parsed_url.port)
  conn.request("GET", parsed_url.path + "?" + parsed_url.query)
  response = conn.getresponse()
  response_data = json.loads(response.read().decode())

  return response_data.get("response").get("records")

def update_dns_record(logger, technitium_token, domain, record_value, new_record_value, type="A"):
  url = f"{TECHNITIUM_UPDATE_RECORDS_URL}?token={technitium_token}&domain={domain}"
  if type == "CNAME":
    url += f"&cname={new_record_value}"
  else:
    url += f"&ipAddress={record_value}&newIpAddress={new_record_value}"

  parsed_url = urllib.parse.urlparse(url)
  conn = http.client.HTTPConnection(parsed_url.hostname, parsed_url.port)
  conn.request("GET", parsed_url.path + "?" + parsed_url.query)
  response = conn.getresponse()
  response_data = json.loads(response.read().decode())

  return response_data.get("status") == "ok"

def add_dns_record(logger, technitium_token, domain, record_value, type="A"):
  url = f"{TECHNITIUM_ADD_RECORDS_URL}?token={technitium_token}&domain={domain}&type={type}"
  if type == "CNAME":
    url += f"&cname={record_value}"
  else:
    url += f"&ipAddress={record_value}"


  parsed_url = urllib.parse.urlparse(url)
  conn = http.client.HTTPConnection(parsed_url.hostname, parsed_url.port)
  conn.request("GET", parsed_url.path + "?" + parsed_url.query)
  response = conn.getresponse()
  response_data = json.loads(response.read().decode())

  return response_data.get("status") == "ok"

def delete_dns_record(logger, technitium_token, domain, record_value, type="A"):
  url = f"{TECHNITIUM_DELETE_RECORDS_URL}?token={technitium_token}&domain={domain}&type={type}"
  if type == "A":
    url += f"&ipAddress={record_value}"

  parsed_url = urllib.parse.urlparse(url)
  conn = http.client.HTTPConnection(parsed_url.hostname, parsed_url.port)
  conn.request("GET", parsed_url.path + "?" + parsed_url.query)
  response = conn.getresponse()
  response_data = json.loads(response.read().decode())

  return response_data.get("status") == "ok"

def clear_dns_cache(logger, technitium_token):
  unsuccessful_zones = []
  for zone in [DEFAULT_ZONE, LAB_ZONE]:
    url = f"{TECHNITIUM_DELETE_DNS_CACHE_URL}?token={technitium_token}&domain={zone}"
    parsed_url = urllib.parse.urlparse(url)
    conn = http.client.HTTPConnection(parsed_url.hostname, parsed_url.port)
    conn.request("GET", parsed_url.path + "?" + parsed_url.query)
    response = conn.getresponse()
    response_data = json.loads(response.read().decode())

    if response_data.get("status") != "ok":
      unsuccessful_zones.append(zone)

  return "Failed to clear cache for zones: " + ", ".join(unsuccessful_zones) if unsuccessful_zones else None

if __name__ == "__main__":
  main()
