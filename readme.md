# fs-quasar

fs-logstash es un ejemplo de como configurar logstash

## Environment
Se necesitan las siguientes variables de entorno para el funcionamiento de logstash:
```
LOGSTASH_JDBC_URL=jdbc:postgresql://<URL>:<PORT>/<DBNAME>?allowPublicKeyRetrieval=true&useSSL=false&verifyServerCertificate=false
LOGSTASH_JDBC_DRIVER=org.postgresql.Driver (en el caso de postgre)
LOGSTASH_JDBC_DRIVER_JAR_LOCATION=/usr/share/logstash/logstash-core/lib/jars/postgresql-connector-java.jar (path especificado en dockerfile)
LOGSTASH_JDBC_USERNAME=<user>
LOGSTASH_JDBC_PASSWORD=<pass>
LOGSTASH_ELASTICSEARCH_HOST=<URL elastic search>
```

## Dockerfile
Dockerfile es utilizado para generar una imagen con todas las dependencias y plugins integrados

Primero se declara la imagen a utilziar
```
FROM docker.elastic.co/logstash/logstash:7.9.0
```
Se instalan plugins necesarios, en este caso solo es necesario instalar logstash-output-elasticsearch
```
RUN /usr/share/logstash/bin/logstash-plugin install logstash-output-elasticsearch
```
Se copian el conector necesario para interactuar con la db y archivos de configuracion dentro del container:
```
COPY ./jdbc-drivers/postgresql-42.2.16.jar /usr/share/logstash/logstash-core/lib/jars/postgresql-connector-java.jar
```
Pipelines yml es el archivo que declara los pipelines que correran dentro de logstash
```
COPY ./config/pipelines.yml /usr/share/logstash/config/pipelines.yml
```
Estos archivos definen el comportamiento de los pipelines (Tambien pueden se puede integrar estos archivos montando una carpeta por ejemplo)
```
COPY ./pipeline/channels.conf /usr/share/logstash/pipeline/channels.conf
COPY ./pipeline/movies.conf /usr/share/logstash/pipeline/movies.conf
COPY ./pipeline/series.conf /usr/share/logstash/pipeline/series.conf
COPY ./pipeline/tv_programs.conf /usr/share/logstash/pipeline/tv_programs.conf
```

## Pipelines.yml
En este archivo se declaran los pipelines. El formato es el siguiente:
```
- pipeline.id: movies
  path.config: "/usr/share/logstash/pipeline/movies.conf"
- pipeline.id: channels
  path.config: "/usr/share/logstash/pipeline/channels.conf"
- pipeline.id: series
  path.config: "/usr/share/logstash/pipeline/series.conf"
- pipeline.id: tv_programs
  path.config: "/usr/share/logstash/pipeline/tv_programs.conf"
```

## Pipeline.conf
La ejecucion de un pipeline esta dividida en 3 etapas, input para la entrada de datos, filter para la manipulacion de estos y output para la salida de datos. Para cada uno de estas etapas Logstash utiliza plugins:

### Input
En este caso utilizamos el plugin [JDBC](https://www.elastic.co/guide/en/logstash/current/plugins-inputs-jdbc.html) para hacer consultas a una base de datos.
Para utilizar este plugin necesitas definir la conexion a una base de datos (para esto las variables de entorno declaradas anteriormente), la frecuencia con la que se ejecutara la consula en formato de crontable (schedule) y la query a ejecutar.

```
input {
  jdbc {
    jdbc_connection_string => "${LOGSTASH_JDBC_URL}"
    jdbc_driver_class => "${LOGSTASH_JDBC_DRIVER}"
    jdbc_driver_library => "${LOGSTASH_JDBC_DRIVER_JAR_LOCATION}"
    jdbc_user => "${LOGSTASH_JDBC_USERNAME}"
    jdbc_password => "${LOGSTASH_JDBC_PASSWORD}"
    schedule => "* * * * *"
    statement => <query>
  }
}
```
### Filter
En el caso de filter utilizamos el plugin [aggregate](https://www.elastic.co/guide/en/logstash/current/plugins-filters-aggregate.html) para mapear los resultados de la consulta en documentos y [Fingerprint](https://www.elastic.co/guide/en/logstash/current/plugins-filters-fingerprint.html) para crear un id de documento y evitar la insercion innecesaria de documentos.
#### Aggregate
Para que sea posible agregar distintas filas en un mismo documento es necesario que la deficinion quede de la siguiente forma:
```
 aggregate {
    task_id => "%{content_id}"
    code => "
      map['content_id'] ||= event.get('content_id')
      ...
    event.cancel()"
    push_previous_map_as_event => true
    timeout => 3
  }
```
El atributo task_id sirve para que logstash entienda varias filas se tratan de un mismo evento mientras que dentro de code se ingresa codigo ruby para definir el mapeo de atributos.
Para definir un atributo en el documento se define de la siguiente forma: 
```ruby 
map['content_id'] ||= event.get('content_id')
```
Para introducir un valor en un array dentro del documento:

```ruby
map['genres'] <<=  event.get('genre')
gen = event.get('genre')
      if ! map['genres'].include?(gen)
        map['genres'] <<=  gen
      end
```
Chequeando si el atributo ya existe dentro del array:
```ruby
gen = event.get('genre')
      if ! map['genres'].include?(gen)
        map['genres'] <<=  gen
      end
```
Agregar un objeto dentro de un array:

```ruby
map['actors'] ||=[]
      actor = {
        'description' => event.get('description'),
        'roleName' => event.get('roleName'),
        'first_name' => event.get('first_name'),
        'last_name' => event.get('last_name')
      }
      if ! map['actors'].include?(actor)
        map['actors'] <<  actor
      end
```

#### Fingerprint
En el caso del plugin fingerprint, la configuracion es la siguiente:
```
filter{
  fingerprint{
    source => "[content_id]"
    method => "SHA256"
    key => "atenea"
    target => "[@metadata][fingerprint]"
  }
}
```
### Output
En el caso de output utilizamos el plugin [Elasticsearch](https://www.elastic.co/guide/en/logstash/current/plugins-outputs-elasticsearch.html) para guardar los documentos genreados en elasticsearch y el plugin [Stdout](https://www.elastic.co/guide/en/logstash/current/plugins-outputs-stdout.html) para imprimir en pantalla los resultados del proceso de filtrado.
```
output {
    stdout { codec => rubydebug }
    elasticsearch {
      hosts => ["${LOGSTASH_ELASTICSEARCH_HOST}"]
      index => "contents_logstash"
      document_id => "%{[@metadata][fingerprint]}"
    }
}


