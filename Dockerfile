FROM ubuntu:focal

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get install -y apt-utils
RUN apt-get install -y ruby ruby-dev build-essential curl nodejs git
RUN gem install bundler
RUN curl -LsS -O https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
RUN bash mariadb_repo_setup --mariadb-server-version=10.6
RUN rm mariadb_repo_setup
RUN apt-get install -y mariadb-server-10.6 mariadb-client-10.6 libmariadb3 libmariadb-dev