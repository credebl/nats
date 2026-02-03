FROM natsio/nats-box:latest

RUN apk add --no-cache aws-cli bash

COPY backup.sh /backup.sh
COPY restore.sh /restore.sh

RUN chmod +x /backup.sh
RUN chmod +x /restore.sh

# CMD ["/restore.sh"]
CMD [ "/backup.sh" ]