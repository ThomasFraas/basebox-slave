# switch Ubuntu download mirror to German server
sudo sed -i 's,http://us.archive.ubuntu.com/ubuntu/,http://ftp.fau.de/ubuntu/,' /etc/apt/sources.list
sudo sed -i 's,http://security.ubuntu.com/ubuntu,http://ftp.fau.de/ubuntu,' /etc/apt/sources.list
sudo apt-get update -y

# set timezone to German timezone
echo "Europe/Berlin" | sudo tee /etc/timezone
sudo dpkg-reconfigure -f noninteractive tzdata

# install development:
sudo apt-get install -y curl git vim

if [ ! -d /vagrant/resources ]
then
  mkdir /vagrant/resources
fi

# make jenkins available on port 80 in network eth0 in vCloud
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j REDIRECT --to-port 8080
# make jenkins available on port 80 in host-only network eth1 in VirtualBox
sudo iptables -t nat -A PREROUTING -i eth1 -p tcp --dport 80 -j REDIRECT --to-port 8080
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo iptables-save | sudo tee /etc/iptables/rules.v4

# install jenkins
wget --no-verbose -O - http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | sudo apt-key add -
echo "deb http://pkg.jenkins-ci.org/debian binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list
sudo apt-get update -y
sudo apt-get install -y jenkins

sudo sed -i 's/#JAVA_ARGS="-Xmx256m"/JAVA_ARGS="-Xmx512m"/g' /etc/default/jenkins

# copy all jenkins config files from host to jenkins installation dir
sudo -u jenkins cp /vagrant/conf/jenkins/* /var/lib/jenkins/

sudo service jenkins restart

echo "Waiting until Jenkins server is up"
while [ ! -f /var/log/jenkins/jenkins.log ]
do
  sleep 5
done
tail -f /var/log/jenkins/jenkins.log | while read LOGLINE
do
  [[ "${LOGLINE}" == *"Jenkins is fully up and running"* ]] && pkill -P $$ tail
done

# retrieve latest version of swarm-client
swarmClientVersion=`curl -s  http://maven.jenkins-ci.org/content/repositories/releases/org/jenkins-ci/plugins/swarm-client/maven-metadata.xml | grep latest | sed 's/\s*[<>a-z/]//g'`
wget --no-verbose -O /vagrant/resources/swarm-client.jar http://maven.jenkins-ci.org/content/repositories/releases/org/jenkins-ci/plugins/swarm-client/$swarmClientVersion/swarm-client-$swarmClientVersion-jar-with-dependencies.jar

while [ ! -f jenkins-cli.jar ]
do
  sleep 10
  wget --no-verbose http://localhost:8080/jnlpJars/jenkins-cli.jar
done
set -x
# force read update list
wget --no-verbose -O default.js http://updates.jenkins-ci.org/update-center.json
sed '1d;$d' default.js > default.json
curl -X POST -H "Accept: application/json" -d @default.json http://localhost:8080/updateCenter/byId/default/postBack --verbose

java -jar jenkins-cli.jar -s http://localhost:8080 install-plugin git
java -jar jenkins-cli.jar -s http://localhost:8080 install-plugin swarm
java -jar jenkins-cli.jar -s http://localhost:8080 install-plugin ansicolor
java -jar jenkins-cli.jar -s http://localhost:8080 install-plugin timestamper
java -jar jenkins-cli.jar -s http://localhost:8080 install-plugin text-finder
java -jar jenkins-cli.jar -s http://localhost:8080 install-plugin ws-cleanup
java -jar jenkins-cli.jar -s http://localhost:8080 install-plugin publish-over-ssh
java -jar jenkins-cli.jar -s http://localhost:8080 install-plugin pegdown-formatter

if [ -f /vagrant/resources/jenkins.plugins.publish_over_ssh.BapSshPublisherPlugin.xml ]; then
  if [ ! -f /var/lib/jenkins/jenkins.plugins.publish_over_ssh.BapSshPublisherPlugin.xml ]; then
    sudo -u jenkins cp /vagrant/resources/jenkins.plugins.publish_over_ssh.BapSshPublisherPlugin.xml /var/lib/jenkins/
  fi
fi

# restart jenkins to activate all plugins
java -jar jenkins-cli.jar -s http://localhost:8080 safe-restart
