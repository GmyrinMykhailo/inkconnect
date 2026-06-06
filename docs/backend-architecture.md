# Архитектура backend InkConnect

## Технологический стек
- Go 1.26
- PostgreSQL 18
- `net/http` для HTTP API и web-страниц
- `pgx` как драйвер PostgreSQL

## Приоритет 1

Уже реализовано:
- запуск backend-сервера
- загрузка конфигурации из `.env`
- подключение к PostgreSQL
- регистрация клиента и мастера
- хеширование пароля
- генерация пары `ed25519` ключей
- сохранение публичного ключа в БД
- создание `master_profiles` для мастеров
- HTML-страница регистрации
- JSON endpoint для регистрации

## Структура проекта

```text
cmd/api                 точка входа приложения
internal/app            сборка зависимостей и запуск сервера
internal/config         конфигурация приложения
internal/http           роутинг и HTTP-слой
internal/http/handlers  обработчики страниц и API
internal/platform       инфраструктурный код
internal/users          домен пользователей и регистрации
web/templates           HTML-шаблоны
web/static              CSS и статические ресурсы
db                      SQL-схема и seed-данные
docs                    документация по архитектуре
```

## Приоритет 2 и 3

Под следующие этапы зарезервированы доменные модули:
- `internal/catalog`
- `internal/appointments`
- `internal/journal`
- `internal/messages`
- `internal/admin`

Их планируемая ответственность:
- `catalog` — каталог мастеров, услуги, фильтры
- `appointments` — запись на процедуру и подтверждение мастером
- `journal` — рекомендации, журнал ухода, проверка целостности
- `messages` — личные сообщения и уведомления
- `admin` — модерация, предупреждения, жалобы

## Основные HTTP маршруты

- `GET /healthz` — проверка состояния сервера
- `GET /register` — HTML-страница регистрации
- `POST /register` — отправка регистрационной формы
- `POST /api/v1/auth/register` — JSON-регистрация для Flutter/Web клиента
