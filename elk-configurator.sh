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
echo -e "${cyan}From Raw Logs to Real-Time Insights!${no_color}"
echo -e "${green}Automate the installation and configuration of Elasticsearch, Kibana, Logstash, and Filebeat, transforming your infrastructure's raw data into actionable intelligence ${no_color}"

# Check for dependencies
echo -e "${cyan}Checking for necessary dependencies...${no_color}"
sudo apt update && sudo apt install -y wget apt-transport-https software-properties-common > /dev/null 2>&1 &
show_loading $!
if [ $? -eq 0 ]; then
  echo -e "${green}Dependencies installed successfully.${no_color}"
else
  echo -e "${red}Failed to install dependencies. Exiting.${no_color}" && exit 1
fi

# Install Java
if prompt_user "Would you like to install Java to enable Elasticsearch functionality?"; then
  echo -e "${cyan}Installing Java...${no_color}"
  sudo apt install -y openjdk-17-jdk > /dev/null 2>&1 &
  show_loading $!
  if [ $? -eq 0 ]; then
    echo -e "${green}Java installed successfully.${no_color}"
  else
    echo -e "${red}Failed to install Java. Exiting.${no_color}" && exit 1
  fi
fi

# Add Elastic Stack Repository
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


# Install & configure Elasticsearch
if prompt_user "Do you want to install Elasticsearch?"; then
  echo -e "${cyan}Installing Elasticsearch...${no_color}"
  sudo apt install -y elasticsearch > /dev/null 2>&1 &
  show_loading $!
  if [ $? -eq 0 ]; then
    sudo systemctl daemon-reload && sudo systemctl start elasticsearch && sudo systemctl enable elasticsearch

    # Configure Elasticsearch
    echo -e "${cyan}Configuring Elasticsearch...${no_color}"

    # Safely configure Elasticsearch by ensuring the desired settings are applied
    sudo sed -i '/^#cluster.name:/c\cluster.name: sample-cluster' /etc/elasticsearch/elasticsearch.yml
    sudo sed -i '/^#node.name:/c\node.name: elasticsearch-node' /etc/elasticsearch/elasticsearch.yml
    sudo sed -i '/^#network.host:/c\network.host: 0.0.0.0' /etc/elasticsearch/elasticsearch.yml
    sudo sed -i '/xpack\.security\.enabled:/c\xpack.security.enabled: false' /etc/elasticsearch/elasticsearch.yml



  # Restart Elasticsearch to apply changes
    sudo systemctl restart elasticsearch

    # Verify Elasticsearch status
    if sudo systemctl status elasticsearch | grep -q "active (running)"; then
      echo -e "${green}Elasticsearch installed and configured successfully.${no_color}"
    else
      echo -e "${red}Failed to restart Elasticsearch. Please check the logs for errors.${no_color}"
      exit 1
    fi
  else
    echo -e "${red}Failed to install Elasticsearch. Exiting.${no_color}" && exit 1
  fi
fi


# Install & configure Kibana
if prompt_user "Do you want to install Kibana?"; then
  echo -e "${cyan}Installing Kibana...${no_color}"
  sudo apt install -y kibana > /dev/null 2>&1 &
  show_loading $!
  if [ $? -eq 0 ]; then
    sudo systemctl start kibana && sudo systemctl enable kibana
    echo -e "${cyan}Configuring Kibana...${no_color}"
    
    # Set Kibana to listen on all network interfaces (remote access)
    sudo sed -i 's/#server.port: 5601/server.port: 5601/' /etc/kibana/kibana.yml
    sudo sed -i 's/#server.host: "localhost"/server.host: "0.0.0.0"/' /etc/kibana/kibana.yml

    # Set Elasticsearch host configuration
    sudo sed -i 's|#elasticsearch.hosts: \["http://localhost:9200"\]|elasticsearch.hosts: ["http://localhost:9200"]|' /etc/kibana/kibana.yml

    # Restart Kibana to apply changes
    if sudo systemctl restart kibana; then
        echo -e "${green}Kibana installed and configured successfully.${no_color}"
    else
        echo -e "${red}Failed to restart Kibana. Please check the logs for errors.${no_color}"
        exit 1
    fi
  fi
fi


# Install & Configure Logstash
if prompt_user "Do you want to install Logstash?"; then
  echo -e "${cyan}Installing Logstash...${no_color}"
  sudo apt install -y logstash > /dev/null 2>&1 &
  show_loading $!
  
  if [ $? -eq 0 ]; then
    # Enable and start Logstash service
   sudo systemctl start logstash && sudo systemctl enable logstash 

    # Configure Logstash
    echo -e "${cyan}Configuring Logstash...${no_color}"

    # Create the input configuration file
    sudo bash -c 'cat << EOF > /etc/logstash/conf.d/02-beats-input.conf
input {
  beats {
    port => 5044
  }
}
EOF'

    # Create the output configuration file
    sudo bash -c 'cat << EOF > /etc/logstash/conf.d/30-elasticsearch-output.conf
output {
  if [@metadata][pipeline] {
    elasticsearch {
      hosts => ["http://localhost:9200"]
      manage_template => false
      index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
      pipeline => "%{[@metadata][pipeline]}"
    }
  } else {
    elasticsearch {
      hosts => ["http://localhost:9200"]
      manage_template => false
      index => "%{[@metadata][beat]}-%{[@metadata][version]}-%{+YYYY.MM.dd}"
    }
  }
}
EOF'

    # Test Logstash configuration
    echo -e "${cyan}Testing Logstash configuration...${no_color}"
    if sudo -u logstash /usr/share/logstash/bin/logstash --path.settings /etc/logstash -t | grep -q "Config Validation Result: OK"; then
      echo -e "${green}Logstash configuration validated successfully.${no_color}"
    else
      echo -e "${red}Logstash configuration validation failed. Please check the configuration files.${no_color}"
      exit 1
    fi

    # Restart Logstash to apply changes
    sudo systemctl restart logstash
    echo -e "${green}Logstash installed and configured successfully.${no_color}"
  else
    echo -e "${red}Failed to install Logstash. Exiting.${no_color}" && exit 1
  fi
fi

# Install and configure Filebeat
if prompt_user "Do you want to install Filebeat?"; then
    echo -e "${cyan}Installing Filebeat...${no_color}"
    sudo apt install -y filebeat > /dev/null 2>&1 &
    show_loading $!
    
    if [ $? -eq 0 ]; then
        echo -e "${cyan}Configuring Filebeat...${no_color}"
        
        # Stop Filebeat if it's running
        sudo systemctl stop filebeat > /dev/null 2>&1
        
        # Backup original configuration
        sudo cp /etc/filebeat/filebeat.yml /etc/filebeat/filebeat.yml.bak
        
        # Configure Filebeat to ship data to Logstash
        sudo tee /etc/filebeat/filebeat.yml > /dev/null << EOL
filebeat.inputs:
- type: filestream
  id: my-filestream-id
  enabled: true
  paths:
    - /var/log/*.log
    - /var/log/syslog

filebeat.config.modules:
  path: \${path.config}/modules.d/*.yml
  reload.enabled: false

setup.template.settings:
  index.number_of_shards: 1

output.logstash:
  hosts: ["localhost:5044"]
  
logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644
EOL

        # Enable system module and configure filesets
        echo -e "${cyan}Enabling and configuring system module...${no_color}"
        sudo filebeat modules disable system > /dev/null 2>&1  # Disable first to ensure clean state
        sudo filebeat modules enable system > /dev/null 2>&1
        
        # Configure system module filesets
        sudo tee /etc/filebeat/modules.d/system.yml > /dev/null << EOL
- module: system
  syslog:
    enabled: true
  auth:
    enabled: true
EOL

        # Test configuration
        echo -e "${cyan}Testing Filebeat configuration...${no_color}"
        if sudo filebeat test config -c /etc/filebeat/filebeat.yml; then
            # Set up ingest pipelines for the system module
            echo -e "${cyan}Setting up ingest pipelines...${no_color}"
            sudo filebeat setup --pipelines --modules system > /dev/null 2>&1
            
            # Set up index management
            echo -e "${cyan}Setting up index management...${no_color}"
            sudo filebeat setup --index-management -E output.logstash.enabled=false \
                -E 'output.elasticsearch.hosts=["localhost:9200"]' > /dev/null 2>&1
            
            # Load Kibana dashboards
            echo -e "${cyan}Loading Kibana dashboards...${no_color}"
            sudo filebeat setup -E output.logstash.enabled=false \
                -E 'output.elasticsearch.hosts=["localhost:9200"]' \
                -E setup.kibana.host=localhost:5601 > /dev/null 2>&1
            
            # Start and enable Filebeat service
            echo -e "${cyan}Starting and enabling Filebeat service...${no_color}"
            
            # Clear any previous startup failures
            sudo systemctl reset-failed filebeat.service > /dev/null 2>&1
            
            # Start Filebeat
            sudo systemctl start filebeat
            
            # Wait a moment to ensure proper startup
            sleep 5
            
            # Check if service is running
            if sudo systemctl is-active --quiet filebeat; then
                sudo systemctl enable filebeat
                echo -e "${green}Filebeat installed and configured successfully.${no_color}"
                echo -e "${cyan}You can check Filebeat status with: sudo systemctl status filebeat${no_color}"
            else
                echo -e "${red}Filebeat service failed to start. Checking logs...${no_color}"
                sudo journalctl -u filebeat --no-pager -n 20
                echo -e "${yellow}Restoring original configuration...${no_color}"
                sudo cp /etc/filebeat/filebeat.yml.bak /etc/filebeat/filebeat.yml
                exit 1
            fi
        else
            echo -e "${red}Filebeat configuration validation failed. Restoring backup...${no_color}"
            sudo cp /etc/filebeat/filebeat.yml.bak /etc/filebeat/filebeat.yml
            exit 1
        fi
    else
        echo -e "${red}Failed to install Filebeat. Please check your internet connection and try again.${no_color}"
        exit 1
    fi
fi


# Final message
echo -e "${green}All selected ELK stack components have been successfully installed and configured for seamless data visualization!${no_color}"



