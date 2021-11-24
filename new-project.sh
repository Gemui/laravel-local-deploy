#!/bin/sh

helpFunction()
{
   echo ""
   echo "Usage: $0 -p projectName -g getLink -m shouldMigrate"
   echo -e "\t-p Enter Project Name"
   echo -e "\t-g Enter Git repo link"
   echo -e "\t-m migrate after install => (require datbase name equal project name)"
   exit 1 # Exit script after printing help
}

while getopts "p:g:m:" opt
do
   case "$opt" in
      p ) projectName="$OPTARG" ;;
      g ) getLink="$OPTARG" ;;
      m ) shouldMigrate="$OPTARG" ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done


# Print helpFunction in case parameters are empty
if [ -z "$projectName" ] || [ -z "$getLink" ]
then
   echo "Some or all of the parameters are empty";
   helpFunction
fi

# 
echo  'Project name' "$projectName"
echo  'Cloning from' "$getLink"

NginxConfigPath="/etc/nginx/conf.d/$projectName.conf"

git clone $getLink $projectName


if [ ! -d $projectName ]
	then 
		echo "Error! Problem with Clonning"  
		exit
fi

# move to project folder and run composer
echo "install app packges..."
cd $projectName && composer install

cp .env.example .env
echo  'Generating Key'
php artisan key:generate

# check migration status 
if [ ! -z "$shouldMigrate" ]
then
	# create new database
	mysql -u root -e "CREATE DATABASE IF NOT EXISTS $projectName COLLATE  utf8mb4_general_ci"
	# change database name in .env

	
	php artisan optimize:clear
	sed -i "s/DB_DATABASE[^\"]*/DB_DATABASE=$projectName/" .env
	sed -i "s/DB_USERNAME[^\"]*/DB_USERNAME=root/" .env
	sed -i "s/DB_PASSWORD[^\"]*/DB_PASSWORD=/" .env
	if [[ $shouldMigrate == "fm" ]]; then
		php artisan migrate:fresh --seed
	else 
		php artisan migrate
	fi

fi


# Set Configuration for nginx 

fileConfigContent="server {\n
    listen 80;\n
    server_name $projectName.develop;\n
    root /var/www/html/$projectName/public;\n
    add_header X-Frame-Options \"SAMEORIGIN\";\n
    add_header X-XSS-Protection \"1; mode=block\";\n
    add_header X-Content-Type-Options \"nosniff\";\n

    index index.php;\n

    charset utf-8;\n

    location / {\n
        try_files "'$uri $uri'"/ /index.php?"'$query_string'";\n
    }\n

    location = /favicon.ico { access_log off; log_not_found off; }\n
    location = /robots.txt  { access_log off; log_not_found off; }\n

    error_page 404 /index.php;\n

    location ~ \.php$ {\n
        include  fastcgi.conf;\n
        fastcgi_pass unix:/var/run/php/php-fpm.sock;\n
        fastcgi_param SCRIPT_FILENAME "'$realpath_root$fastcgi_script_name'";\n
        #include fastcgi_params;\n
        
    }

    location ~ /\.(?!well-known).* {\n
        deny all;\n
    }\n
}"


echo 'Set Configuration File'
LocalConfigFile="$projectName.conf"
HostsFile="127.0.0.1	$projectName.develop"
echo $fileConfigContent > "$LocalConfigFile"

sudo bash -c "mv $LocalConfigFile /etc/nginx/conf.d && echo $HostsFile >> /etc/hosts"

echo 'restart Nginx'
systemctl restart nginx
