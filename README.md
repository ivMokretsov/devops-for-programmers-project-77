### Hexlet tests and linter status:
[![Actions Status](https://github.com/ivMokretsov/devops-for-programmers-project-77/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/ivMokretsov/devops-for-programmers-project-77/actions)


## Подготовительный этап
- Для начала работы необходимо иметь авторизованный ключ
он должен находится в директории проекта в файле key.json
[подробнее в документации](https://yandex.cloud/ru/docs/tutorials/infrastructure-management/terraform-quickstart#console_2)

- Все чувствительные данные хранятся в директории `/ansible/group_vars/all/vault.yml` в зашифрованном виде.
Ключ необходимо положить в директорию проекта в файле `.vault_pass`
---
## Основные шаги
- Сгенерировать IAM-токен
    ```
    make get-iam-token
    ```
    плейбук автоматически сгенерирует зашифрованный токен для терраформ `/ansible/group_vars/all/iam_token_vault.yml`
- Создать инфраструктуру
    ```
    make init
    make apply
    ```
- Развернуть сервис на хостах
    ```
    make configure
    ```

### Сервис доступен по адресу https://mokretsov.ru/
> в случае необходимости проверки просьба написать в MM