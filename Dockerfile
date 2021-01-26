FROM docker.elastic.co/logstash/logstash:7.9.0

#Required Dependencies
RUN /usr/share/logstash/bin/logstash-plugin install logstash-output-elasticsearch

# Copy PostgreSQL connector to container
COPY --chown=logstash:logstash ./jdbc-drivers/postgresql-42.2.16.jar /usr/share/logstash/logstash-core/lib/jars/postgresql-connector-java.jar

#Copy pipelines configuration to container
COPY --chown=logstash:logstash ./config/pipelines.yml /usr/share/logstash/config/pipelines.yml

#Copy pipelines definition to container (this can be done by mounting volumes)
COPY --chown=logstash:logstash ./pipeline/channels.conf /usr/share/logstash/pipeline/channels.conf
COPY --chown=logstash:logstash ./pipeline/movies.conf /usr/share/logstash/pipeline/movies.conf
COPY --chown=logstash:logstash ./pipeline/series.conf /usr/share/logstash/pipeline/series.conf
COPY --chown=logstash:logstash ./pipeline/tv_programs.conf /usr/share/logstash/pipeline/tv_programs.conf
