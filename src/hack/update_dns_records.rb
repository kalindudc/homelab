#!/usr/bin/env ruby

require "net/http"
require "uri"
require "json"
require "openssl"
require "time"
require "logger"
require "open3"

SECRETS_FILE_PATH = "#{File.expand_path("../..", File.dirname(__FILE__))}/config/secrets.ejson"

OMADA_CONTROLLER_IP = "192.168.0.110"
OMADA_CONTROLLER_PORT = 443
OMADA_BASE_URL = "https://#{OMADA_CONTROLLER_IP}:#{OMADA_CONTROLLER_PORT}"

TECHNITIUM_DNS_IP = "192.168.50.100"
TECHNITUM_DNS_PORT = "5380"
TECHNITIUM_ADD_RECORDS_URL = "http://#{TECHNITIUM_DNS_IP}:#{TECHNITUM_DNS_PORT}/api/zones/records/add"

DEFAULT_ZONE = "home.arpa"
LAB_ZONE = "lab.home.arpa"

LAB_HOSTNAMES = ["collie", "terrier", "retriever", "shepherd"]

def main
  # validate SECRETS_FILE_PATH exists
  if !File.file?(SECRETS_FILE_PATH)
    raise "Secrets file not found at #{SECRETS_FILE_PATH}"
    exit 1
  end

  # decrypt secrets file
  secrets = decrypt_ejson(SECRETS_FILE_PATH)

  omada_id = secrets["omada_id"]
  client_id = secrets["omada_client_id"]
  client_secret = secrets["omada_client_secret"]
  technitium_token = secrets["technitium_dns_access_token"]

  # Set up logger
  logger = Logger.new(STDOUT)
  logger.level = Logger::DEBUG
  logger.datetime_format = "%Y-%m-%d %H:%M:%S"

  omada_access_token, omada_token_expiry = get_access_token(logger, omada_id, client_id, client_secret)
  if omada_access_token.nil?
    logger.error("Failed to acquire access token.")
    return
  end

  omada_devices = get_omada_devices(logger, omada_id, omada_access_token, omada_token_expiry)
  if omada_devices.empty?
    logger.error("Failed to acquire devices.")
    exit 1
  end

  logger.info("Omada devices acquired successfully.")
  logger.info("Found #{omada_devices.length} devices.")

  err = update_dns_records(logger, technitium_token, omada_devices)
  if err
    logger.error("Failed to update DNS records: #{err}.")
    exit 1
  end
  logger.info("DNS records updated successfully.")
end

private

def update_dns_records(logger, technitium_token, omada_devices)
  unsuccessful_records = []
  omada_devices.each do |hostname, ip_address|
    domain = "#{hostname}.#{DEFAULT_ZONE}"
    if LAB_HOSTNAMES.include?(hostname)
      domain = "#{hostname}.#{LAB_ZONE}"
    end

    url = URI.parse("#{TECHNITIUM_ADD_RECORDS_URL}?token=#{technitium_token}&domain=#{domain}&type=A&ipAddress=#{ip_address}")
    http = Net::HTTP.new(url.host, url.port)

    request = Net::HTTP::Get.new(url)
    response = http.request(request)
    response_data = JSON.parse(response.body)

    if response_data["status"] != "ok"
      unsuccessful_records << domain
    end
  end

  unsuccessful_records.empty? ? nil : "Failed to update records: #{unsuccessful_records.join(", ")}"
end

def decrypt_ejson(file)
  stdout, stderr, status = Open3.capture3("ejson decrypt #{file}")
  raise "Failed to decrypt #{file}: #{stderr}" unless status.success?
  JSON.parse(stdout)
end

# Function to get a new access token
def get_access_token(logger, omada_id, client_id, client_secret)
  url = URI.parse("#{OMADA_BASE_URL}/openapi/authorize/token?grant_type=client_credentials")
  headers = { "Content-Type" => "application/json" }
  data = { omadacId: omada_id, client_id: client_id, client_secret: client_secret }

  http = Net::HTTP.new(url.host, url.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE

  request = Net::HTTP::Post.new(url, headers)
  request.body = data.to_json
  response = http.request(request)
  response_data = JSON.parse(response.body)

  access_token, token_expiry = nil, nil

  if response_data["errorCode"] == 0
    access_token = response_data["result"]["accessToken"]
    expires_in = response_data["result"]["expiresIn"]
    token_expiry = Time.now + expires_in
    logger.info("Access token acquired successfully.")
  else
    logger.error("Failed to acquire access token.")
  end

  return access_token, token_expiry
end

# Function to check if the token is expired
def token_expired?(token_expiry)
  token_expiry.nil? || Time.now > token_expiry
end

# Function to get device information from Omada Controller
def get_omada_devices(logger, omada_id, access_token, token_expiry)
  get_access_token(logger) if token_expired?(token_expiry)

  headers = { "Authorization" => "AccessToken=#{access_token}" }

  current_page = 1
  page_size = 100
  total_devices = -1
  devices_count = 0

  device_info = {}

  loop do
    devices_url = URI.parse("#{OMADA_BASE_URL}/openapi/v1/#{omada_id}/sites/Default/clients?page=#{current_page}&pageSize=#{page_size}")

    http = Net::HTTP.new(devices_url.host, devices_url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new(devices_url, headers)
    response = http.request(request)

    response_data = JSON.parse(response.body)
    if response_data["errorCode"] != 0
      logger.error("Failed to acquire devices.")
      return {}
    end

    result = response_data["result"]
    total_devices = result["totalRows"] if total_devices < 0

    devices_count = [devices_count + page_size, total_devices].min
    devices = result["data"]

    devices.each do |device|
      hostname = device["name"]
      ip_address = device["ip"]
      device_info[hostname.downcase.gsub("_", "-").gsub(" ", "-").gsub(".", "-")] = ip_address if hostname && ip_address
    end

    break if devices_count >= total_devices

    current_page += 1
  end

  device_info
end

main
