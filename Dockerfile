FROM erlio/docker-vernemq

ADD https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh /usr/sbin/wait-for-it.sh
COPY bin/vernemq.sh /usr/sbin/start_vernemq
RUN chmod +x /usr/sbin/wait-for-it.sh