#! /bin/bash
set -euo pipefail

tmp=$(mktemp -d)
cleanup() {
    rm -rf $tmp
}

trap cleanup ERR

external=14809
internal=14810
server=""
bin=""
secret=""

help() {
    echo "usage: $(basename $0) [FLAGS]"
    echo "Deploy nginx for thin"
    echo
    echo "  -h  Display help text"
    echo "  -e  External port for nginx to listen on (put this in github)"
    echo "  -i  Internal port for thin to listen on (run thin with this port)"
    echo "  -n  Nginx server name"
    echo "  -s  Github secret"
    echo "  -c  Command to call in systemd service"
}

while getopts "he:i:n:s:c:" flag; do
case $flag in
    h) help; exit 0;;
    e) external=$OPTARG;;
    i) internal=$OPTARG;;
    n) server=$OPTARG;;
    s) secret=$OPTARG;;
    c) bin=$OPTARG;;
    \?) echo Unknown option; help; exit 1;;
esac
done

if [[ $server == "" ]];then
    echo "You need to set -s for the server name for nginx" >&2
    help
    exit 1
fi

if [[ $bin == "" ]];then
    echo "You need to set -b for the command to be called for the systemd service" >&2
    help
    exit 1
fi

echo "Using nginx port $external and internal port $internal for thin"
echo "Server name: $server"

s="systemctl --user"

set -x

sudo apt update
sudo apt install -y nginx openssl

mkdir -p ~/.local/bin
git clone https://github.com/AnthonyHewins/thin.git $tmp
cd $tmp
make thin
mv bin/thin ~/.local/bin
cleanup

dir=/etc/nginx
sudo mkdir -p $dir/conf.d $dir/ssl
dir+=/ssl
sudo openssl genrsa -out $dir/selfsigned.key 2048
sudo openssl req -new -key $dir/selfsigned.key -out $dir/selfsigned.csr
sudo openssl x509 -req -days 3650 -in $dir/selfsigned.csr -signkey $dir/selfsigned.key -out $dir/selfsigned.crt

dir=/etc/nginx
cat <<EOF | sudo tee $dir/conf.d/selfsigned.conf
ssl_certificate /etc/nginx/ssl/selfsigned.crt;
ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
EOF

cat <<EOF | sudo tee $dir/sites-available/thin-webhook.conf
server {
    listen $external ssl;

    include conf.d/selfsigned.conf;
    server_name $server;

    client_max_body_size 32M;

    location /github/webhook {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_pass http://127.0.0.1:$internal;
    }
}
EOF
cd $dir/sites-enabled
ln -s ../sites-available/thin-webhook.conf thin-webhook
sudo systemctl restart nginx

dir=~/.config/systemd/user
mkdir -p $dir
cat <<EOF > $dir/thin.service
[Unit]
Description=Github webhook server

[Service]
Type=simple
Restart=on-failure
RestartSec=5m
Environment=SECRET=$secret
ExecStart=/home/%u/.local/bin/thin -p $internal -cmd $bin

[Install]
WantedBy=default.target
EOF

s daemon-reload
s enable thin.service
s start thin.service
