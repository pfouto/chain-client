FROM openjdk:17-alpine

WORKDIR code
ADD deploy/client/* ./

ENTRYPOINT ["java", "-cp", "chain-client.jar:.", "site.ycsb.Client" ,"-t", "-s", "-P", "config.properties"]