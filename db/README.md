# База данных InkConnect

Базовая схема PostgreSQL находится в [schema.sql](/C:/Users/mihai/OneDrive/Desktop/4kurs/Inkconnect/db/schema.sql).

Что покрывает схема:
- пользователи с ролями `client`, `master`, `admin`
- профиль мастера, услуги и портфолио
- запись клиента к мастеру
- защищённый журнал ухода
- рекомендации мастера и подтверждения клиента
- личные сообщения, отзывы и действия администратора

## Как запустить готовую базу через Docker

1. Скопируйте `.env.example` в `.env`, если хотите поменять логин, пароль, имя БД или порт.
2. Запустите:

```powershell
docker compose up -d
```

PostgreSQL будет доступен по адресу:
- host: `localhost`
- port: `5432`
- database: `inkconnect`
- user: `inkconnect`
- password: `inkconnect_dev`

При первом запуске автоматически применятся:
- [schema.sql](/C:/Users/mihai/OneDrive/Desktop/4kurs/Inkconnect/db/schema.sql)
- [seed.sql](/C:/Users/mihai/OneDrive/Desktop/4kurs/Inkconnect/db/seed.sql)

## Как пересоздать базу с нуля

```powershell
docker compose down -v
docker compose up -d
```

## Ключевая идея защищённого журнала

Неизменяемость журнала обеспечивается таблицей `care_journal_entries`:
- `previous_entry_id` и `previous_hash` связывают запись с предыдущей
- `entry_hash` хранит хэш текущей записи
- `digital_signature` хранит подпись автора записи
- `payload` позволяет сохранять детали в JSONB без постоянной миграции схемы

Рекомендуемый подход в Go-сервисе:
- мастер создаёт рекомендацию
- сервер формирует каноническую строку записи
- вычисляется хэш записи
- запись подписывается приватным ключом пользователя
- `latest_hash` в `care_journals` обновляется после вставки новой записи

## Демо-данные

После первого запуска будут доступны тестовые записи:
- администратор: `admin@inkconnect.local`
- мастер: `master@inkconnect.local`
- клиент: `client@inkconnect.local`
- демо-услуга, запись на процедуру, журнал ухода, сообщения и отзыв
