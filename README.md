# Сборка на основе Alpine с помощью Werf

---
## Содержание:
- [x] [Официальная документация](https://ru.werf.io/documentation/v1.2/reference/werf_yaml.html)
- [x] [Структура репозитория](#структура-репозитория):
  - [Назначение папок и файлов](#назначение-папок-и-файлов)
- [x] [Шаблон dev.tmpl.yml](#шаблон-devtmplyml) 
- [x] [Описание Helm Chart'а](#описание-helm-chartа)
  - [Данные и секреты](#данные-и-секреты)
  - [Ресурсы кластера Kubernates и Go-шаблоны](#ресурсы-кластера-kubernates-и-go-шаблоны)
- [x] [Кратко о werf.yaml на примере](кратко-о-werfyaml-на-примере)
- [x] [Возможности Makefile'а](#возможности-makefileа)
  - [Доступные команды](#доступные-команды)
- [x] [CI/CD](#cicd)


---
## Структура репозитория
```
[.docker]
    [kube.app]
    [kube.web]
    dev.tmpl.yml
[.helm]
    [secret]
    [templates]
    Chart.yaml
    secret-values.yaml
    values.yaml
    unit.json
[.werf]
    base-install.tmpl
    dev-additinal.tmpl
[src]
    .env.local
    composer.json
Makefile
werf.yaml
werf-giterminism.yaml
```

### Назначение папок и файлов:
- ```.docker``` - содержит каталоги с файлами, которые необходимы для сборки соответствующих образов.
- ```.docker/dev.tmpl.yml``` - шаблон, на основе которого генерируется docker-compose.yml файл, используемый для запуска окружения на компьютере разработчика
- ```.helm``` - Helm Chart, переменные, секреты, конфигурации
- ```.werv/base-install.tmpl``` - базовый список пакетов, устанавливаемый на основной рабочий образ. 
- ```.werv/dev-additinal.tmpl``` - дополнительные компоненты, устанавливаемые на образ, используемый в разработке. Данный образ НЕ участвует в *Prod* окружении.   
- ```src``` - код проекта
- ```src/.env.local``` - переменные, используемые только в разработке. Для остальных окружений, переменные задаются в файлах ```.helm/values.yaml``` и ```.helm/secret-values.yaml```
- ```Makefile``` - используется только в разработке. Помогает в локальной сборке, запуске и т.д.
- ```werf.yaml``` - описание процесса сборки контейнеров
- ```werf-giterminism.yaml``` - различные настройки сборщика werf

## Шаблон dev.tmpl.yml
[Документация по использованию шаблонов при генерации docker-compose](https://ru.werf.io/documentation/v1.2/reference/cli/werf_compose_config.html#docker-composeyaml)

Werf предоставляет дополнительные инструменты при работе с docker-compose, такими, как:
- Динамические имена актуальных образов
- Возможность подставлять различные переменные
- Применять при генерации [Go-шаблоны](https://pkg.go.dev/text/template#hdr-Actions)

Данный шаблон используется для генерации статического файла docker-compose.yml, который в дальнейшем, используется в процессе запуска окружения.
В дальнейшем, возможно, не будем использовать статический файл, а полностью перейдем на использование werf.

В представленном примере используются такие возможности: 
- Динамические имена образов `image: $WERF_TOOLS_DOCKER_IMAGE_NAME`. 
Вместо переменной подставится имя образа для контейнера tools из файла werf.yaml (см. `image: tools`)
Имя переменной состоит из 3х частей:
  - служебного слова `WERF` - все переменные, относящиеся к werf имеют такую приставку
  - имени образа в werf.yaml `TOOLS` в верхнем регистре.
  - служебного окончания `DOCKER_IMAGE_NAME`. Если имя образа в werf.yaml файле составное, например `tools_for_dev`, то переменная будет называться так: `WERF_TOOLS_FOR_DEV_DOCKER_IMAGE_NAME`.
- Следующая версия этого примера, будет дополнена использованием переменных среды, для задания учетных данных и др.

## Описание Helm Chart'а
[Документация на сайте werf.io](https://ru.werf.io/documentation/v1.2/advanced/helm/configuration/chart.html)

Каталог `.helm/templates` содержит манифесты с включенными Go-шаблонами. При выкатки с помощью `werf converge`, обрабатываются все шаблоны, подставляются переменные и т.д. 
Более подробно написано в официальной документации. 
Здесь можно обратить на ряд моментов (которые так же есть в официальной документации):
- Порядок применения манифестов определяется не числом в имени манифеста, а [весом](https://ru.werf.io/documentation/v1.2/reference/deploy_annotations.html#resource-weight) `weight`, указанным с описании ресурса Kubernetes. 
  Чем меньше вес, тем раньше применяется данный манифест. И наоборот, чем больше вес - тем позже. 
  При наличии манифестов с одинаковым весом, они применяютсмя одновременно. 
  Werf каждый раз дожидается применения манифестов с одним весом, прежде чем применить следующие. 
  Это очень полезно для поэтапного вывода приложения, например, сначала надо поднять базу данных и redis, затем накатить миграцию и только после этого запустить само приложение.  
  Пример из [50-job-migrate.yaml](.helm/templates/50-job-migrate.yaml#L6): 
  ```yaml
  metadata:
    annotations:
      werf.io/weight: "50"
    ...
  ```
- Для запуска миграций, удобно применять Job'ы. 
  Но, для того, чтобы Job удалился после выполнения, можно использовать соответствующую опцию `ttlSecondsAfterFinished` с указанием времени после удачного завершения в секундах для последующего удаления.  
  Пример из [50-job-migrate.yaml](.helm/templates/50-job-migrate.yaml#L8):
  ```yaml  
  apiVersion: batch/v1
  kind: Job
  metadata:
    name: job-migrate
    annotations:
      werf.io/weight: "50"
  spec:
    ttlSecondsAfterFinished: 30
    template:
      spec:
      ...
  ```
- Переменные в манифест передаются с помощью специальных вставок в стиле Go (см. [Ресурсы кластера Kubernates и Go-шаблоны](#ресурсы-кластера-kubernates-и-go-шаблоны)). 

### Данные и секреты
Механизм хранения переменных хорошо расписан в документации werf:
- [Обычные пользовательские данные](https://ru.werf.io/documentation/v1.2/advanced/helm/configuration/values.html#%D0%BE%D0%B1%D1%8B%D1%87%D0%BD%D1%8B%D0%B5-%D0%BF%D0%BE%D0%BB%D1%8C%D0%B7%D0%BE%D0%B2%D0%B0%D1%82%D0%B5%D0%BB%D1%8C%D1%81%D0%BA%D0%B8%D0%B5-%D0%B4%D0%B0%D0%BD%D0%BD%D1%8B%D0%B5)
- [Пользовательские секреты](https://ru.werf.io/documentation/v1.2/advanced/helm/configuration/values.html#%D0%BF%D0%BE%D0%BB%D1%8C%D0%B7%D0%BE%D0%B2%D0%B0%D1%82%D0%B5%D0%BB%D1%8C%D1%81%D0%BA%D0%B8%D0%B5-%D1%81%D0%B5%D0%BA%D1%80%D0%B5%D1%82%D1%8B)
- [Ключ шифрования](https://ru.werf.io/documentation/v1.2/advanced/helm/configuration/secrets.html#%D0%BA%D0%BB%D1%8E%D1%87-%D1%88%D0%B8%D1%84%D1%80%D0%BE%D0%B2%D0%B0%D0%BD%D0%B8%D1%8F)
- [Сервисные данные](https://ru.werf.io/documentation/v1.2/advanced/helm/configuration/values.html#%D1%81%D0%B5%D1%80%D0%B2%D0%B8%D1%81%D0%BD%D1%8B%D0%B5-%D0%B4%D0%B0%D0%BD%D0%BD%D1%8B%D0%B5)

Для организации хранения переменных, мы используем структуру, в которой можно указать значения переменных, в зависимости от используемого окружения.  
Например, значение переменной `APP_ENV` в окружении `test = testing`, в окружении `prod = production`, а во всех остальных (по умолчанию) - `testing`.  
Переменная `APP_NAME` для всех окружений равна `%CHARTNAME%` (Об этом "лайф-хаке" в главе ниже)  
Пример из [.helm/values.yaml](.helm/values.yaml#L12-22) (Обычные пользовательские данные) 
  ```yaml
  app-env:
    APP_NAME:
      _default: "%CHARTNAME%"
    APP_ENV:
      test: testing
      stage: production
      prod: production
      _default: testing
    APP_KEY:
      prod: "base64:dGVzdC1hcHBsaWNhdGlvbi1wcm9kCg=="
      _default: "base64:dGVzdC1hcHBsaWNhdGlvbi1kZWZhdWx0Cg=="
  ...
  ```
Werf позволяет хранить переменные в зашифрованном виде. Структура аналогичная, за исключением того, что все значения зашифрованы с помощью алгоритма AES-128 или AES-256
Пример хранения секретов из [.helm/secret-values.yaml](.helm/secret-values.yaml#L18-25) (Пользовательские секреты)
  ```yaml
  app-env:
  ...
    REDIS_HOST:
      _default: 10005e70c0f878b5e2e629e68ae2d94358bdb608f6f8bb3b77f6e3752ea620028b4e
      stage: 100057e70cc6d0a7e6a40246cab7643da07c6d0b649a90c7c5d3e20e4848dd3f671b
      prod: 100006341f8177cfa08a48e453e6b7d6d58563a77a32815558eaebc550a233dbb357aca53a3ebbe1f02e6810f27508fe2400
    REDIS_PASSWORD:
      _default: 1000b7571885578c6cdd1503392c01ab823f69027673dae222f0c4ae3210f5c7e4b5
      stage: 1000c96496afd81de7f52755e7174534f7b2ddb4d880e71f0072f402b0d1eaf3f7f2
      prod: 1000e58fb3c2d1a5c6aafb697d2a73a9fbc98003e647758265e035dbddd0b37bde07
  ...
  ```
Папка [.helm/secret](.helm/secret) содержит зашифрованные файлы сертификатов.  
Краткий список команд для работы с секретами:
- `werf helm secret generate-secret-key` - генерация 32-битного ключа шифрования
- `werf helm secret values edit .helm/secret-values.yaml` - редактирование файла секретов
- `werf helm secret file encrypt <fileName>` - зашифровать файл
- `werf helm secret file decrypt <fileName>` - расшифровать файл
Ключ шифрование хранится в переменной CI/CD `WERF_SECRET_KEY` и задается в gitlab->Settings->CI/CD->Variables. Обязательна установка атрибута `Masked` и снятие `Protected`. 
Доступ к просмотру и изменению переменных имеют только Maintainers и Owners. 



### Ресурсы кластера Kubernates и Go-шаблоны
- [Документация по Go шаблонам](https://ru.werf.io/documentation/v1.2/advanced/helm/configuration/templates.html)
- [Шаблонизатор werf.yaml](https://ru.werf.io/documentation/v1.2/reference/werf_yaml_template_engine.html)
- [Документация по Spring функциям](https://masterminds.github.io/sprig/)
- [Документация по дополнительным функциям Helm](https://helm.sh/docs/howto/charts_tips_and_tricks/)  

На примере ниже, показаны варианты использования Go-шаблонов.   
Здесь, в примере, в качестве имени образа `image:` подставляется текущий (созданный для конкретного коммита) образ из локального Docker репозитория.
  Так же в этом примере, интерес представляет подстановка переменной `REDIS_PASSWORD` в зависимости от окружения `env`(environment).
  Кратко: берем массив `REDIS_PASSWORD`, в нем ищем ключ совпадающий с окружением, если ключ не найден, подставляем значение из ключа `_default`, который обязан присутствовать.
  Более подробно о рекомендуемом способе организации хранения переменных, см. [Данные и секреты](#данные-и-секреты).  
  Пример из [20-depl-redis.yaml](.helm/templates/20-depl-redis.yaml#L23-28):
  ```yaml
      ...
      containers:
        - name: redis
          image: {{ .Values.werf.image.redis }}
          command:
            - redis-server
            {{- $valMap := pluck "REDIS_PASSWORD" $.Values.env | first }}
            {{- $val := pluck $.Values.global.env $valMap | first | default $valMap._default }}
            - --requirepass {{  $val }}
      ...
  ```

Формирование `ConfigMap` с необходимыми значениями переменных (в зависимости от окружения env) происходит в [10-configmap.yaml](.helm/templates/10-configmap.yaml#L9-18). Так же, как и в примере выше, выбираем из всего массива переменных значения ключей в соответствии с окружением env. 
Затем, если встречаются "ключевые слова" `%NAMESPACE%` или `%CHARTNAME%`, подставляем вместо них, глобальные значения. Это сделано по причине того, что в файл переменных нельзя включать Go-шаблоны (ограничение werf).
О процессе объединения переменных хорошо рассказано в [официальной документации](https://ru.werf.io/documentation/v1.2/advanced/helm/configuration/values.html#%D0%B8%D1%82%D0%BE%D0%B3%D0%BE%D0%B2%D0%BE%D0%B5-%D0%BE%D0%B1%D1%8A%D0%B5%D0%B4%D0%B8%D0%BD%D0%B5%D0%BD%D0%B8%D0%B5-%D0%B4%D0%B0%D0%BD%D0%BD%D1%8B%D1%85).
Если кратко, то сначала расшифровываются зашифрованные ключи из `secret-values.yaml`, объединяются с `values.yaml` и другими значениями и далее идут в работу общим массивом. 
Поэтому, мы не заботимся о расшифровке чувствительных данных - это делается прозрачно и налету самим werf'ом.
  ```yaml
  ...
  data:
    .env: |
    {{- range $name, $value := .Values.env }}
      {{- $val := pluck $.Values.global.env $value | first | default $value._default }}
      {{- $val := print $val | replace "%NAMESPACE%" $.Values.werf.namespace }}
      {{- $val := print $val | replace "%CHARTNAME%" $.Chart.Name }}
      {{ $name }}={{ $val }}
      {{- /*
             Можно добавлять новые замены по аналогии со строкой выше (replace....)
             Это сделано для тех переменных, которые зависят от окружения, но в values.yaml нельзя передать им эти значения
      */ -}}
    {{- end }}
  ```

Еще один "интересный" момент - хранение и использование ssl ключей. Перед помещением их в репозиторий, они шифруются командой `werf helm secret file encrypt <fileName>`.
Затем, в процессе деплоя, werf сам их расшифровывает и мы их можем использовать, как обычные файлы.
В манифесте [90-tls.yaml](.helm/templates/90-tls.yaml) формируется ресурс Secret содержащий сертификат и закрытый ключ.
Функция `werf_secret_file` расшифровывает файл, а `b64enc` пререводит его в base64 для хранения в манифесте.
  ```yaml
  ...
  data:
    tls.crt: {{ werf_secret_file "osis-test.crt" | b64enc  }}
    tls.key: {{ werf_secret_file "osis-test.key" | b64enc  }}
  ```

## Кратко о werf.yaml на примере
- [Документация werf.yaml](https://ru.werf.io/documentation/v1.2/reference/werf_yaml.html)
- [Шаблонизатор werf.yaml](https://ru.werf.io/documentation/v1.2/reference/werf_yaml_template_engine.html)
- [Гитерминизм](https://ru.werf.io/documentation/v1.2/reference/werf_giterminism_yaml.html)

Основные моменты, на примере [текущего проекта](werf.yaml#L1-8). Некоторые "основные" моменты: 
- Шапка с указанием имени проекта и namespace при деплое в кластер Kubernetes. Для определения namespaсe, используется переменная с именем проекта и ветки репозитория:
  ```yaml
  project: ex-alpine
  configVersion: 1
  deploy:
    namespace: >-
      [[ project ]]-{{ env "CI_COMMIT_REF_SLUG" }}
  ...
  ```
- Сборка начального образа - [base-img](werf.yaml#L21-49). В определении имени образа применяется "финт ушами" - в зависимости от наличия переменной `CI_NEXUS_RLS_LOGIN`, делаем вывод о том, с какого репозитория брать образ (глобальный, либо корпоративный).
  Сборка данного образа состоит из 2х этапов: выполнения команд (после `setup:`) и выполнения опций Docker (после `docker:`)
  ```yaml
  ...
  image: base-img
  from: {{ if ne (env "CI_NEXUS_RLS_LOGIN") "-" }}harbor.rncb.ru/rls/{{ end }}alpine:3.17.0
  shell:
    setup:
      - set -ex
      ...
  docker:
    WORKDIR: /www
  ---
  ...
  ```
- Определяем необходимость использования nexus-rls.rncb.ru для скачивания пакетов Alpine и настройка авторизации в нем (стр. [29-32](werf.yaml#L29-32)):
  ```yaml
  ...
    {{- if ne (env "CI_NEXUS_RLS_LOGIN") "-" }} # Для локальной сборки это не нужно - прокси не используется
      - unset http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY
      - sed -i "s/dl-cdn.alpinelinux.org/{{ env "CI_NEXUS_RLS_LOGIN" }}:{{ env "CI_NEXUS_RLS_PWD" }}@nexus-rls.rncb.ru\/repository/" /etc/apk/repositories
  {{- end }}
  ...
  ```
- Используем include для выноса из основного файла в [дополнительный](.werf/base-install.tmpl), различных компонент, необходимых для работы приложения в Prod окружении ([стр. 40](werf.yaml#L40)). `indent 4` - отступ 4 пробелов.
  ```yaml
  ...
  {{ include "base-install.tmpl" . | indent 4 }}
  ...
  ```
- Для образа, который будет использоваться при разработке и не окажется в Prod окружении, можно установить дополнительные компоненты. Их выносим в отдельный [файл](.werf/dev-additinal.tmpl)([стр.76](werf.yaml#L76)):
  ```yaml
  ...
  {{ include "dev-additinal.tmpl" . | indent 4 }}
  ...
  ```
- При установки модулей PHP из внутренней сети, должен быть использован nexus-rls.rncb.ru с авторизацией. Настройка composer делается так ([стр. 124-126](werf.yaml#L124-126)):
  ```yaml
  ...
  - composer config --global repositories.name composer https://{{ env "CI_NEXUS_RLS_LOGIN" }}:{{ env "CI_NEXUS_RLS_PWD" }}@nexus-rls.rncb.ru/repository/composer/
  - composer config --global repositories.packagist.org false
  - echo "{\"http-basic\":{\"nexus-rls.rncb.ru\":{\"username\":\""{{ env "CI_NEXUS_RLS_LOGIN" }}"\",\"password\":\""{{ env "CI_NEXUS_RLS_PWD" }}"\"}}}">~/.composer/auth.json
  ...
  ```
- По аналогии, можно настроить npm ([стр.128-130](werf.yaml#L128-130)):
  ```yaml
    ...
    - NPM_AUTH=`echo -n "{{ env "CI_NEXUS_RLS_LOGIN" }}:{{ env "CI_NEXUS_RLS_PWD" }}"|base64`
    - npm config set -g registry=https://nexus-rls.rncb.ru/repository/npm-proxy/
    - npm config set -g //nexus-rls.rncb.ru/repository/npm-proxy/:_auth=${NPM_AUTH}
    ...
  ```
- Необходимость настройки работы через nexus-rls.rncb.ru определяем по наличию переменной ([стр. 121](werf.yaml#L121)):
  ```yaml
  ...
  {{- if ne (env "CI_NEXUS_RLS_LOGIN") "-" }}
  ...
  {{- end }}
  ...
  ```
- А значение '-' присвается переменной `CI_NEXUS_RLS_LOGIN` при использовании [Makefile (стр. 7-14)](Makefile#L7-14). Команда `make` используется только при разработки, а во время разработки может И использоваться nexus и НЕ использоваться. 
  Но, в рамках CI, Nexus всегда используется.



## Возможности Makefile'а
С помощью Makefile автоматизируются рутинные процессы сборки и запуска окружения, в процессе разработки приложения. 
Makefile используется только в процессе разработки и только для того, чтобы помочь "поднять" приложение на локальном компьютере.
При этом, поднимаются несколько контейнеров, необходимых для работы конкретного приложения, например: база данных, сервер MinioS3, почтовый сервер и т.д. 
Но, в то же время используется код приложения из директории ```src```, а переменные среды из файла ```src/.env.local```, которые монтируется внутрь соответствующих контейнеров. 
Это дает возможность в реальном времени отслеживать изменения, проводимые в коде.

#### Доступные команды: 
- `make install` - Установка werf на локальный компьютер, в зависимости от ОС
- `make build` - Build образов, необходимых для разработки. Здесь используются не все образы (см. [Шаблон dev.tmpl.yml](#Шаблон dev.tmpl.yml))
- `make start`, `make stop`, `make restart`, `make status` - Запуск, останов и рестарт всех контейнеров окружения, статус работы контейнеров
- `make init` - Запуск первоначальной настройки приложения (создание директорий, миграции и т.д.)
- `make shell` - Вход "внутрь" контейнера с приложением, для возможности выполнения каких-либо ручных операций (запуск composer, npm и т.д.)
- `mate test` - Запуск Unit тестов, если они имеются
- `make clean` - Остановка окружения, удаление всех docker образов, удаление временных файлов.


## CI/CD
#### Переменные:
- [PROJECT_NAME](.gitlab-ci.yml#L7) - Для избежания разночтений, желательно указывать такой же, как и в werf.conf
- [WERF_REPO](.gitlab-ci.yml#L10) - Основной репозиторий, где хранятся все стадии сборки
- [FINAL_REPO](.gitlab-ci.yml#L11) - Сюда попадают только конечные стадии сборки. Данный репозиторий настроен так, что все артефакты, записанные в `harbor.rncb.ru/osis-final`, копируются в `nexus-rls.rncb.ru/osis`. Таким образом обеспечивается дублирование критической информации.
- [WERF_NAMESPACE](.gitlab-ci.yml#L16) - Namespace при выкатке в Kubernetes. Здесь мы используем имя ветки, для возможности организации тестовых сред у каждой ветки репозитория
- [SONAR_PROJECT_NAME](.gitlab-ci.yml#L17) - Имя проекта в [Sonarqube](https://sonarqube.rncb.ru/). Необходимо предварительно его там создать.

#### Стадии:
- **build** - Сборка образов. Для master и main веток перемещение из основного репозитория в финальный, откуда образ копируется в общебанковский репозиторий автоматически. Для остальных веток - сборка образов. Так же в рамках этой стадии, [может запускаться Unit тестирование](.gitlab-ci.yml#L62-80) (Здесь не реализовано)
- **Secure Scan**, **Code Scanning**, **Security**, **Reports** - Сканирование кода и финального образа на безопасность. Для этого достаточно добавить [соответствующие строки в CI](.gitlab-ci.yml#L170-200), все остальное вынесено в отдельный репозиторий.  
  Сканирование выполняется для main, master, stage, developer веток. Перед сканированием, необходимо [создание файла image.txt](.gitlab-ci.yml#L171-191)
- **deploy** - Деплой приложения. Здесь представлено 2 сценария: [деплой в Kubernetes](.gitlab-ci.yml#L139-146) и [деплой на ВМ](.gitlab-ci.yml#L148-166). Но используется только первый сценарий.
  В процессе деплоя, организуются [окружения (Environments)](https://gl.rncb.ru/osis/examples/werf_alpine/-/environments)  см. [стр. 86-90](.gitlab-ci.yml#L86-90). В каждом окружении публикуется именно тот код, который находится в конкретной ветке репозитория.
  Так же, для освобождения вычислительных ресурсов кластера Kubernetes, используется автоматическое [удаление окружения](.gitlab-ci.yml#L88-89) запуском стадии [dismiss](.gitlab-ci.yml#L118-135). 
- **dismiss** - Удаление окружения. При удалении ветки, удаляется и окружение.
В данном примере, для ветки master, так же задано автоматическое удаление. **В рабочем проекте - это недопустимо**.

