#! /bin/bash
set -euo pipefail

external=14809
internal=14810
server=""

help() {
    echo "usage: $(basename $0) [FLAGS]"
    echo "Deploy nginx for thin"
    echo
    echo "  -h  Display help text"
    echo "  -e  External port for nginx to listen on (put this in github)"
    echo "  -i  Internal port for thin to listen on (run thin with this port)"
    echo "  -s  Server name for nginx"
}

while getopts "he:i:" flag; do
case $flag in
    h) help; exit 0;;
    e) external=$OPTARG;;
    i) internal=$OPTARG;;
    s) server=$OPTARG;;
    \?) echo Unknown option; help; exit 1;;
esac
done

if [[ $server == "" ]];then
    echo "You need to set -s for the server name for nginx" >&2
    help
    exit 1
fi

echo "Using nginx port $external and internal port $internal for thin"
echo "Server name: $server"
set -x

sudo apt update
sudo apt install -y nginx openssl

dir=$(mktemp -d)
git clone github.com/AnthonyHewins/thin $dir
cd $dir
make -f $dir/Makefile thin
mv $dir

dir=/etc/nginx
mkdir -p $dir/conf.d $dir/ssl
dir+=/ssl
openssl genrsa -out $dir/selfsigned.key 2048
openssl req -new -key $dir/selfsigned.key -out $dir/selfsigned.csr
openssl x509 -req -days 3650 -in $dir/selfsigned.csr -signkey $dir/selfsigned.key -out $dir/selfsigned.crt

dir=/etc/nginx
cat <<EOF > $dir/conf.d/selfsigned.conf
ssl_certificate /etc/nginx/ssl/selfsigned.crt;
ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
EOF

cat <<EOF > $dir/sites-available/thin-webhook.conf
server {
    listen $external ssl;

    include conf.d/self-signed.conf;
    server_name $server;

    client_max_body_size 32M;

    location /github/webhook {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_pass http://127.0.0.1:$internal;
    }
}
EOF

dir=~/.config/systemd/user
mkdir -p $dir
echo <<EOF > $dir/thin.service
[Unit]
Description=Github webhook server

[Service]
Type=simple
Restart=on-failure
RestartSec=5m
ExecStart=/home/%u/.local/bin/thin

[Install]
WantedBy=default.target
EOF