
enable_bbr()
{
    enable_bbr_force()
    {
        echo "BBR not enabled. Enabling BBR..."
        echo 'net.core.default_qdisc=fq' | tee -a /etc/sysctl.conf
        echo 'net.ipv4.tcp_congestion_control=bbr' | tee -a /etc/sysctl.conf
        sysctl -p
    }
    sysctl net.ipv4.tcp_available_congestion_control | grep -q bbr ||  enable_bbr_force
}

get_port()
{
    while true; 
    do
        local PORT=$(shuf -i 40000-65000 -n 1)
        ss -lpn | grep -q ":$PORT " || echo $PORT && break
    done
}

open_port()
{
    port_to_open="$1"
    if [[ "$port_to_open" == "" ]]; then
        echo "You must specify a port!'"
        return 9
    fi

    ufw allow $port_to_open/tcp
    ufw reload
}

add_caddy_proxy()
{
    domain_name="$1"
    local_port="$2"
    cat /etc/caddy/Caddyfile | grep -q "an easy way" && echo "" > /etc/caddy/Caddyfile
    echo "
$domain_name {
    reverse_proxy /* 127.0.0.1:$local_port
}" >> /etc/caddy/Caddyfile
    systemctl restart caddy.service
}

install_tracer()
{
    server="$1"
    echo "Installing Aiursoft Tracer to domain $server..."
    
    port=$(get_port) && echo Using internal port: $port
    cd ~

    # Valid domain is required
    if [[ "$server" == "" ]]; then
        echo "You must specify your server domain. Try execute with 'bash -s www.a.com'"
        return 9
    fi

    # Enable BBR
    enable_bbr

    # Install basic packages
    echo "Installing packages..."
    wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -r -s)/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    dpkg -i packages-microsoft-prod.deb && rm ./packages-microsoft-prod.deb
    cat /etc/apt/sources.list.d/caddy-fury.list | grep -q caddy || echo "deb [trusted=yes] https://apt.fury.io/caddy/ /" | tee -a /etc/apt/sources.list.d/caddy-fury.list
    apt update
    apt install -y apt-transport-https curl git vim dotnet-sdk-3.1 caddy
    apt autoremove -y

    # Download the source code
    echo 'Downloading the source code...'
    ls | grep -q Tracer && rm ./Tracer -rvf
    git clone https://github.com/AiursoftWeb/Tracer.git

    # Build the code
    echo 'Building the source code...'
    tracer_path="$(pwd)/Apps/TracerApp"
    dotnet publish -c Release -o $tracer_path ./Tracer/Tracer.csproj

    # Register tracer service
    echo "Registering Tracer service..."
    echo "[Unit]
    Description=Tracer Service
    After=network.target
    Wants=network.target

    [Service]
    Type=simple
    ExecStart=/usr/bin/dotnet $tracer_path/Tracer.dll --urls=http://localhost:$port/
    WorkingDirectory=$tracer_path
    Restart=on-failure
    RestartPreventExitStatus=23

    [Install]
    WantedBy=multi-user.target" > /etc/systemd/system/tracer.service
    systemctl enable tracer.service
    systemctl start tracer.service

    # Config caddy
    echo 'Configuring the web proxy...'
    add_caddy_proxy $server $port

    # Config firewall
    open_port 443
    open_port 80

    # Finish the installation
    echo "Successfully installed Tracer as a service in your machine! Please open https://$server to try it now!"
    echo "Strongly suggest run 'sudo apt upgrade' on machine!"
    echo "Strongly suggest to reboot the machine!"
}

install_tracer "$@"
