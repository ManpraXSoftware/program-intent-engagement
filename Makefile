.DEFAULT_GOAL := help

.PHONY: help clean piptools requirements ci_requirements dev_requirements \
        validation_requirements doc_requirements production-requirements static shell \
        test coverage isort_check isort style lint quality pii_check validate \
        migrate html_coverage upgrade extract_translation dummy_translations \
        compile_translations fake_translations pull_translations \
        push_translations start-devstack open-devstack pkg-devstack \
        detect_changed_source_translations validate_translations check_keywords

define BROWSER_PYSCRIPT
import os, webbrowser, sys
try:
	from urllib import pathname2url
except:
	from urllib.request import pathname2url

webbrowser.open("file://" + pathname2url(os.path.abspath(sys.argv[1])))
endef
export BROWSER_PYSCRIPT
BROWSER := python -c "$$BROWSER_PYSCRIPT"

# Generates a help message. Borrowed from https://github.com/pydanny/cookiecutter-djangopackage.
help: ## display this help message
	@echo "Please use \`make <target>\` where <target> is one of"
	@awk -F ':.*?## ' '/^[a-zA-Z]/ && NF==2 {printf "\033[36m  %-25s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

clean: ## delete generated byte code and coverage reports
	find . -name '*.pyc' -delete
	coverage erase
	rm -rf assets
	rm -rf pii_report

piptools: ## install pinned version of pip-compile and pip-sync
	pip install -r requirements/pip.txt
	pip install -r requirements/pip-tools.txt

requirements: piptools dev_requirements ## sync to default requirements

ci_requirements: validation_requirements ## sync to requirements needed for CI checks

dev_requirements: ## sync to requirements for local development
	pip-sync -q requirements/dev.txt requirements/private.*

validation_requirements: ## sync to requirements for testing & code quality checking
	pip-sync -q requirements/validation.txt

doc_requirements:
	pip-sync -q requirements/doc.txt

production-requirements: ## install requirements for production
	pip-sync -q requirements/production.txt

static: ## generate static files
	python manage.py collectstatic --noinput

shell: ## run Django shell
	python manage.py shell

test: clean ## run tests and generate coverage report
	pytest

# To be run from CI context
coverage: clean
	pytest --cov-report html
	$(BROWSER) htmlcov/index.html

isort_check: ## check that isort has been run
	isort --check-only program_intent_engagement/

isort: ## run isort to sort imports in all Python files
	isort --recursive --atomic program_intent_engagement/

style: ## run Python style checker
	pylint --rcfile=pylintrc program_intent_engagement *.py

lint: ## run Python code linting
	pylint --rcfile=pylintrc program_intent_engagement *.py

quality:
	tox -e quality

pii_check: ## check for PII annotations on all Django models
	DJANGO_SETTINGS_MODULE=program_intent_engagement.settings.test \
	code_annotations django_find_annotations --config_file .pii_annotations.yml --lint --report --coverage

check_keywords: ## Scan the Django models in all installed apps in this project for restricted field names
	python manage.py check_reserved_keywords --override_file db_keyword_overrides.yml

validate: test quality pii_check check_keywords ## run tests, quality, and PII annotation checks

migrate: ## apply database migrations
	python manage.py migrate

html_coverage: ## generate and view HTML coverage report
	coverage html && open htmlcov/index.html

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: piptools ## update the requirements/*.txt files with the latest packages satisfying requirements/*.in
	# Make sure to compile files after any other files they include!
	pip-compile --upgrade --allow-unsafe --rebuild -o requirements/pip.txt requirements/pip.in
	pip-compile --upgrade -o requirements/pip-tools.txt requirements/pip-tools.in
	pip-compile --upgrade -o requirements/base.txt requirements/base.in
	pip-compile --upgrade -o requirements/test.txt requirements/test.in
	pip-compile --upgrade -o requirements/doc.txt requirements/doc.in
	pip-compile --upgrade -o requirements/quality.txt requirements/quality.in
	pip-compile --upgrade -o requirements/validation.txt requirements/validation.in
	pip-compile --upgrade -o requirements/ci.txt requirements/ci.in
	pip-compile --upgrade -o requirements/dev.txt requirements/dev.in
	pip-compile --upgrade -o requirements/production.txt requirements/production.in
	# Let tox control the Django version for tests
	grep -e "^django==" requirements/base.txt > requirements/django.txt
	sed '/^[dD]jango==/d' requirements/test.txt > requirements/test.tmp
	mv requirements/test.tmp requirements/test.txt

extract_translations: ## extract strings to be translated, outputting .mo files
	python manage.py makemessages -l en -v1 -d django
	python manage.py makemessages -l en -v1 -d djangojs

dummy_translations: ## generate dummy translation (.po) files
	cd program_intent_engagement && i18n_tool dummy

compile_translations: # compile translation files, outputting .po files for each supported language
	python manage.py compilemessages

fake_translations: ## generate and compile dummy translation files

pull_translations: ## pull translations from Transifex
	tx pull -t -af --mode reviewed

push_translations: ## push source translation files (.po) from Transifex
	tx push -s

start-devstack: ## run a local development copy of the server
	docker-compose --x-networking up

open-devstack: ## open a shell on the server started by start-devstack
	docker exec -it program_intent_engagement /edx/app/program-intent-engagement/devstack.sh open

pkg-devstack: ## build the program_intent_engagement image from the latest configuration and code
	docker build -t program_intent_engagement:latest -f docker/build/program-intent-engagement/Dockerfile git://github.com/edx/configuration

detect_changed_source_translations: ## check if translation files are up-to-date
	cd program_intent_engagement && i18n_tool changed

validate_translations: fake_translations detect_changed_source_translations ## install fake translations and check if translation files are up-to-date

docker_build:
	docker build . -f Dockerfile -t openedx/program_intent_engagement

travis_docker_tag: docker_build
	docker tag openedx/program_intent_engagement openedx/program_intent_engagement:$$TRAVIS_COMMIT

travis_docker_auth:
	echo "$$DOCKER_PASSWORD" | docker login -u "$$DOCKER_USERNAME" --password-stdin

travis_docker_push: travis_docker_tag travis_docker_auth ## push to docker hub
	docker push 'openedx/program_intent_engagement:latest'
	docker push "openedx/program_intent_engagement:$$TRAVIS_COMMIT"

# devstack-themed shortcuts
dev.up: # Starts all containers
	docker-compose up -d

dev.up.build:
	docker-compose up -d --build

dev.down: # Kills containers and all of their data that isn't in volumes
	docker-compose down

dev.stop: # Stops containers so they can be restarted
	docker-compose stop

app-shell: # Run the app shell as root
	docker exec -u 0 -it program_intent_engagement.app bash

db-shell: # Run the app shell as root, enter the app's database
	docker exec -u 0 -it program_intent_engagement.db mysql -u root program_intent_engagement

%-logs: # View the logs of the specified service container
	docker-compose logs -f --tail=500 $*

%-restart: # Restart the specified service container
	docker-compose restart $*

%-attach:
	docker attach program_intent_engagement.$*

github_docker_build:
	docker build . -f Dockerfile --target app -t openedx/program_intent_engagement

github_docker_tag: github_docker_build
	docker tag openedx/program_intent_engagement openedx/program_intent_engagement:${GITHUB_SHA}

github_docker_auth:
	echo "$$DOCKERHUB_PASSWORD" | docker login -u "$$DOCKERHUB_USERNAME" --password-stdin

github_docker_push: github_docker_tag github_docker_auth ## push to docker hub
	docker push 'openedx/program_intent_engagement:latest'
	docker push "openedx/program_intent_engagement:${GITHUB_SHA}"

selfcheck: ## check that the Makefile is well-formed
	@echo "The Makefile is well-formed."
