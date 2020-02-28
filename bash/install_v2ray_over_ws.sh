#/usr/bin/bash

domain='72x.me'
fakesite='https://github.com/daoye/blog.git'
userid=`uuidgen`

usr=`whoami`
if [ "$usr" != "root" ]
then
    echo 'Use "sudo" to run this script. '
    exit 1
fi

echo Installing dependency libraries...
sudo apt-get update
sudo apt-get install software-properties-common
sudo add-apt-repository universe
sudo add-apt-repository ppa:certbot/certbot
sudo apt-get update

apt install -y nginx git certbot python-certbot-nginx

systemctl stop nginx.service

bbr=`lsmod | grep bbr`
if [ -z "$bbr" ]
then
    echo Enable bbr

    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

    sysctl -p
fi

rm -rf /var/www/wwwroot/fake_site
mkdir -p /var/www/wwwroot/fake_site

echo Downloading fake site...
cd /var/www/wwwroot/fake_site
git clone ${fakesite} .
cd -

cat>/var/www/wwwroot/fake_site/robots.txt<<EOF
User-agent: *
Disallow:/
EOF

echo Register ssl cert.
sudo certbot certonly --standalone -d ${domain}

cat>/etc/nginx/conf.d/v2ray.conf<<EOF
    server {
        listen       80;
        server_name  ${domain};

        location / {
            root   /var/www/wwwroot/fake_site;
            index  index.html index.html;
        }
    }

    server {
        listen 443 ssl;
        ssl on;
        ssl_certificate       /etc/letsencrypt/live/${domain}/cert.pem;
        ssl_certificate_key   /etc/letsencrypt/live/${domain}/privkey.pem;
        ssl_protocols         TLSv1 TLSv1.1 TLSv1.2;
        ssl_ciphers           HIGH:!aNULL:!MD5;
        server_name           ${domain};

        location / {
            root   /var/www/wwwroot/fake_site;
            index  index.html index.html;
        }

        location /subscribe { 
            proxy_redirect off;
            proxy_pass http://127.0.0.1:8678; 
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$http_host;

            # Show realip in v2ray access.log
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
      }
    }
EOF

echo Installing v2ray...
_=`curl -L -s https://install.direct/go.sh|bash`

systemctl stop v2ray.service


cat>/etc/v2ray/config.json<<EOF
{
    "inbounds": [{
        "port": 8678,
        "listen":"127.0.0.1",
        "protocol": "vmess",
        "settings": {
            "clients": [{
                  "id": "${userid}",
                  "level": 1,
                  "alterId": 64
            }]
        },
        "streamSettings": {
          "network": "ws",
          "wsSettings": {
              "path": "/subscribe"
          }
        }
    }],
    "outbounds": [{
        "protocol": "freedom",
        "settings": {}
    }]
}
EOF

systemctl enable v2ray.service
systemctl enable nginx.service
systemctl start v2ray.service
systemctl start nginx.service

echo v2ray user id is: [ ${userid} ]
echo Install done
