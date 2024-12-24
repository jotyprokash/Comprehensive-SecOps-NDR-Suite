#!/bin/bash

# Color definitions for better visibility
green='\033[0;32m'
red='\033[0;31m'
cyan='\033[0;36m'
yellow='\033[0;33m'
no_color='\033[0m'

# Function to display a loading animation
show_loading() {
  local pid=$1
  local delay=0.1
  local spinner=("|" "/" "-" "\\")
  while [ -d /proc/$pid ]; do
    for i in "${spinner[@]}"; do
      echo -ne "\r${yellow}Installing... $i${no_color}"
      sleep $delay
    done
  done
  echo -ne "\r"
}

# Function to prompt the user and check their response
prompt_user() {
  while true; do
    read -p "$1 [y/n]: " response
    case "$response" in
      [yY][eE][sS]|[yY]) return 0 ;;
      [nN][oO]|[nN]) echo -e "${red}Skipping this step as per user input.${no_color}" && return 1 ;;
      *) echo -e "${yellow}Invalid input. Please type y or n.${no_color}" ;;
    esac
  done
}

# Welcome message
echo -e "${cyan}ELK Deployment Script${no_color}"
echo -e "${green}This script will install Elasticsearch, Kibana, Logstash, and Filebeat on your system.${no_color}"

# Step 1: Check for dependencies
echo -e "${cyan}Checking for necessary dependencies...${no_color}"
sudo apt update && sudo apt install -y wget apt-transport-https software-properties-common > /dev/null 2>&1 &
show_loading $!
if [ $? -eq 0 ]; then
  echo -e "${green}Dependencies installed successfully.${no_color}"
else
  echo -e "${red}Failed to install dependencies. Exiting.${no_color}" && exit 1
fi

# Step 2: Install Java
if prompt_user "Do you want to install Java (required for Elasticsearch)?"; then
  echo -e "${cyan}Installing Java...${no_color}"
  sudo apt install -y openjdk-17-jdk > /dev/null 2>&1 &
  show_loading $!
  if [ $? -eq 0 ]; then
    echo -e "${green}Java installed successfully.${no_color}"
  else
    echo -e "${red}Failed to install Java. Exiting.${no_color}" && exit 1
  fi
fi

# Step 3: Add Elastic Stack Repository
echo -e "${cyan}Adding Elastic Stack repository...${no_color}"
sudo mkdir -p /etc/apt/keyrings && sudo wget -qO /etc/apt/keyrings/GPG-KEY-elasticsearch https://artifacts.elastic.co/GPG-KEY-elasticsearch && \
echo "deb [signed-by=/etc/apt/keyrings/GPG-KEY-elasticsearch] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list > /dev/null && \
sudo apt update > /dev/null 2>&1 &
show_loading $!
if [ $? -eq 0 ]; then
  echo -e "${green}Elastic Stack repository added successfully.${no_color}"
else
  echo -e "${red}Failed to add Elastic Stack repository. Exiting.${no_color}" && exit 1
fi

# Step 4: Install Elasticsearch
if prompt_user "Do you want to install Elasticsearch?"; then
  echo -e "${cyan}Installing Elasticsearch...${no_color}"
  sudo apt install -y elasticsearch > /dev/null 2>&1 &
  show_loading $!
  if [ $? -eq 0 ]; then
    sudo systemctl daemon-reload && sudo systemctl enable elasticsearch && sudo systemctl start elasticsearch

    echo -e "${cyan}Configuring Elasticsearch...${no_color}"
    sudo sed -i 's/#cluster.name: my-application/cluster.name: sample-cluster/' /etc/elasticsearch/elasticsearch.yml
    sudo sed -i 's/#node.name: node-1/node.name: elasticsearch-node/' /etc/elasticsearch/elasticsearch.yml
    sudo sed -i 's/#network.host: 192.168.0.1/network.host: 0.0.0.0/' /etc/elasticsearch/elasticsearch.yml
    sudo sed -i 's/#discovery.type: single-node/discovery.type: single-node/' /etc/elasticsearch/elasticsearch.yml
    sudo sed -i 's/#xpack.security.enabled: true/xpack.security.enabled: false/' /etc/elasticsearch/elasticsearch.yml
    sudo sed -i 's/#xpack.monitoring.enabled: true/xpack.monitoring.enabled: false/' /etc/elasticsearch/elasticsearch.yml

    sudo systemctl restart elasticsearch
    echo -e "${green}Elasticsearch installed and configured successfully.${no_color}"
  else
    echo -e "${red}Failed to install Elasticsearch. Exiting.${no_color}" && exit 1
  fi
fi

# Step 5: Install Kibana
if prompt_user "Do you want to install Kibana?"; then
  echo -e "${cyan}Installing Kibana...${no_color}"
  sudo apt install -y kibana > /dev/null 2>&1 &
  show_loading $!
  if [ $? -eq 0 ]; then
    sudo systemctl enable kibana && sudo systemctl start kibana

    echo -e "${cyan}Configuring Kibana...${no_color}"
    sudo sed -i 's/#server.host: "localhost"/server.host: "0.0.0.0"/' /etc/kibana/kibana.yml
    sudo sed -i 's/#elasticsearch.hosts: \["http:\/\/localhost:9200"\]/elasticsearch.hosts: \["http:\/\/localhost:9200"\]/' /etc/kibana/kibana.yml

    sudo systemctl restart kibana
    echo -e "${green}Kibana installed and configured successfully.${no_color}"
  else
    echo -e "${red}Failed to install Kibana. Exiting.${no_color}" && exit 1
  fi
fi

# Step 6: Install Logstash
if prompt_user "Do you want to install Logstash?"; then
  echo -e "${cyan}Installing Logstash...${no_color}"
  sudo apt install -y logstash > /dev/null 2>&1 &
  show_loading $!
  if [ $? -eq 0 ]; then
    sudo systemctl enable logstash && sudo systemctl start logstash

    echo -e "${cyan}Configuring Logstash...${no_color}"
    sudo bash -c 'cat << EOF > /etc/logstash/conf.d/logstash.conf
input { beats { port => 5044 } }
output { elasticsearch { hosts => ["http://localhost:9200"] } }
EOF'

    sudo systemctl restart logstash
    echo -e "${green}Logstash installed and configured successfully.${no_color}"
  else
    echo -e "${red}Failed to install Logstash. Exiting.${no_color}" && exit 1
  fi
fi

# Step 7: Install Filebeat
if prompt_user "Do you want to install Filebeat?"; then
  echo -e "${cyan}Installing Filebeat...${no_color}"
  sudo apt install -y filebeat > /dev/null 2>&1 &
  show_loading $!
  if [ $? -eq 0 ]; then
    sudo systemctl enable filebeat && sudo systemctl start filebeat

    echo -e "${cyan}Configuring Filebeat...${no_color}"
    sudo filebeat modules enable system
    sudo filebeat setup --pipelines --modules system > /dev/null 2>&1
    sudo filebeat setup --index-management > /dev/null 2>&1

    echo -e "${green}Filebeat installed and configured successfully.${no_color}"
  else
    echo -e "${red}Failed to install Filebeat. Exiting.${no_color}" && exit 1
  fi
fi

# Final message
echo -e "${green}All selected components of the ELK stack have been installed and configured successfully!${no_color}"
