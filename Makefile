COMPOSE_FILE = dev.yml

# Версия Werf - жедательно та, которая используется на gitlab-runner
WerfRelease := 1.2.183

# Для локальной разработки эта переменная не задана - при сборке не будет использовать прокси см. werf.yaml
ifndef CI_NEXUS_RLS_LOGIN
    $(info === Working without proxy === )
    export CI_NEXUS_RLS_LOGIN = -
    export CI_COMMIT_REF_SLUG = developer
    export WERF_ENV = local
 else
    $(info === Working with proxy === )
endif

# Проверим наличие конфига приложения для локальной сборки (Для остальных сред используется .helm/values )
ifneq ("$(wildcard src/.env.local)","")
    $(info Using src/.env.local )
else
    $(error You should make a "src/.env.local" file. See ReadMe)
endif

# Определим версию OS
ifeq ($(OS),Windows_NT)     # is Windows_NT on XP, 2000, 7, Vista, 10...
    OS  := windows
    CPU := amd64
else
    UNAME_S := $(shell sh -c 'uname -s 2>/dev/null || echo Unknown')
    ifeq ($(UNAME_S),Linux)
        OS = linux
    endif
    ifeq ($(UNAME_S),Darwin)
        OS = darwin
    endif

    UNAME_P := $(shell sh -c 'uname -p 2>/dev/null || echo Unknown')
    ifeq ($(UNAME_P),x86_64)
        OSFLAG = amd64
    endif
    ifneq ($(filter arm%,$(UNAME_P)),)
        OSFLAG = arm64
    endif
endif

# Определим UID:GID для запуска локальных контейнеров с правами текущего пользователя (Потом добавлю, пока это сложно для понимания ;) )
MAKE_UID := $(shell sh -c 'id -u')
MAKE_GID := $(shell sh -c 'id -g')
PROJECT_NAME := $(shell sh -c 'cat werf.yaml | grep "^project" | sed "s/.*://; s/ //g"')


build:
	@echo "Login: [$$CI_NEXUS_RLS_LOGIN]"
	werf build tools db redis minio mailhog webserver
	@cp .docker/dev.tmpl.yml ./
	werf compose config --skip-build --docker-compose-options="-f dev.tmpl.yml" --quiet > $(COMPOSE_FILE)
	@rm -f dev.tmpl.yml
start:
	docker-compose -f $(COMPOSE_FILE) up -d --no-recreate
	docker-compose -f $(COMPOSE_FILE) stop -t 1 init
	docker-compose -f $(COMPOSE_FILE) rm -f init
stop:
	docker-compose -f $(COMPOSE_FILE) down --remove-orphans
status:
	docker-compose -f $(COMPOSE_FILE) ps
restart:
	make stop && make start
init:
	docker-compose -f $(COMPOSE_FILE) exec app composer app:storage:create
	docker-compose -f $(COMPOSE_FILE) exec app chmod -R 755 /www/storage/logs
# 	docker-compose -f $(COMPOSE_FILE) exec redis1 redis-cli -a password --cluster-yes --cluster create 10.47.5.21:6379 10.47.5.22:6379 10.47.5.23:6379 || :
	docker-compose -f $(COMPOSE_FILE) exec app composer update --no-scripts | grep -v "#St"
	docker-compose -f $(COMPOSE_FILE) exec app composer install --no-scripts | grep -v "#St"
shell:
	docker-compose -f $(COMPOSE_FILE) exec app sh
test:
	docker-compose -f $(COMPOSE_FILE) exec app composer test
clean:
	make stop
	docker-compose -f $(COMPOSE_FILE) up --no-deps -d app
	docker-compose -f $(COMPOSE_FILE) exec app rm -Rf /Full/storage
	docker-compose -f $(COMPOSE_FILE) exec app rm -Rf storage/app/public storage/logs storage/framework/cache/data storage/framework/sessions storage/framework/views storage/framework/testing
	docker-compose -f $(COMPOSE_FILE) exec app rm -Rf vendor
	make stop
	docker rmi `cat $(COMPOSE_FILE) |grep "image:"|sed "s/^.*image: //"` 2>/dev/null ||:
	docker rmi `docker images|awk '{print $$1 ":" $$2}'| grep "${PROJECT_NAME}:"` 2>/dev/null ||:
	docker rmi `werf config render|grep "^from:"|awk '{print $2}'` 2>/dev/null ||:

install:
	curl --output /tmp/werf https://tuf.werf.io/targets/releases/$(WerfRelease)/$(OS)-$(OSFLAG)/bin/werf ||:
	chmod +x /tmp/werf
	sudo mv /tmp/werf /usr/bin/
    # Существующие файлы для скачивания:
    # https://tuf.werf.io/targets/releases/1.2.183/darwin-amd64/bin/werf
    # https://tuf.werf.io/targets/releases/1.2.183/darwin-arm64/bin/werf
    # https://tuf.werf.io/targets/releases/1.2.183/linux-amd64/bin/werf
    # https://tuf.werf.io/targets/releases/1.2.183/linux-arm64/bin/werf
    # https://tuf.werf.io/targets/releases/1.2.183/windows-amd64/bin/werf.exe

