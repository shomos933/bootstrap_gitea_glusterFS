#!/bin/bash
# Скрипт настройки логов: ежедневная ротация, хранение логов за 7 дней,
# оптимизация конфигураций logrotate, настройка systemd-journald и создание cron-задачи для очистки старых файлов.
# Логи работы данного скрипта будут записаны в файле deploy_project.log в корне проекта.

LOGFILE=\"$(dirname $0)/../../../deploy_project.log\"

# Функция логирования с меткой времени
log() {
    echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] \$1\" | tee -a \"$LOGFILE\"
}

if [[ \$EUID -ne 0 ]]; then
    echo \"ERROR: Скрипт должен запускаться от root!\" 1>&2
    exit 1
fi

log \"==== Начало настройки логов: \$(date) ====\"

# 1. Обновление глобального файла logrotate.conf
log \"1. Обновление /etc/logrotate.conf для ежедневной ротации с хранением 7 дней\"
cat <<'EOF' > /etc/logrotate.conf
daily
rotate 7
create
dateext
compress
include /etc/logrotate.d
EOF
if [[ \$? -eq 0 ]]; then
    log \"   [SUCCESS] /etc/logrotate.conf обновлён.\"
else
    log \"   [ERROR] Не удалось обновить /etc/logrotate.conf.\"
fi

# 2. Оптимизация файлов в /etc/logrotate.d/
log \"2. Оптимизация файлов в /etc/logrotate.d/ для ежедневной ротации\"
for file in /etc/logrotate.d/*; do
    [ -f \"\$file\" ] || continue
    log \"   Обработка файла: \$file\"
    sed -i -E 's/(weekly|monthly)/daily/g' \"\$file\"
    sed -i -E 's/rotate[[:space:]]+[0-9]+/rotate 7/g' \"\$file\"
    sed -i -E 's/^#(compress)/\1/g' \"\$file\"
    if ! grep -q \"compress\" \"\$file\"; then\n        sed -i '/create/ a compress' \"\$file\"\n    fi\n    if [[ \$? -eq 0 ]]; then\n        log \"      [SUCCESS] Файл \$file обработан.\"\n    else\n        log \"      [ERROR] Проблема при обработке файла \$file.\"\n    fi\ndone

# 3. Настройка systemd-journald
if systemctl --version &>/dev/null; then
    log \"3. Настройка systemd-journald (/etc/systemd/journald.conf)\"
    cat <<'EOF' > /etc/systemd/journald.conf
[Journal]
SystemMaxUse=100M
SystemKeepFree=50M
SystemMaxFileSize=25M
MaxRetentionSec=604800
EOF
    if [[ \$? -eq 0 ]]; then\n        log \"   [SUCCESS] /etc/systemd/journald.conf обновлён.\"\n        systemctl restart systemd-journald\n        if [[ \$? -eq 0 ]]; then\n            log \"   [SUCCESS] systemd-journald перезапущен.\"\n        else\n            log \"   [ERROR] Не удалось перезапустить systemd-journald.\"\n        fi\n    else\n        log \"   [ERROR] Не удалось обновить /etc/systemd/journald.conf.\"\n    fi\nelse\n    log \"   [INFO] systemctl не найден, пропускаем настройку journald.\"\nfi

# 4. Создание cron-задачи для очистки файлов старше 7 дней
log \"4. Создание cron-задачи для очистки файлов старше 7 дней (/etc/cron.daily/clean_old_logs)\"
cat <<'EOF' > /etc/cron.daily/clean_old_logs
#!/bin/bash
find /var/log -type f -name \"*.log.*\" -mtime +7 -delete
find /tmp -type f -mtime +7 -delete
EOF
chmod +x /etc/cron.daily/clean_old_logs
if [[ \$? -eq 0 ]]; then\n    log \"   [SUCCESS] Cron-задача создана.\"\nelse\n    log \"   [ERROR] Не удалось создать cron-задачу.\"\nfi

# 5. Принудительный запуск logrotate для проверки конфигурации
log \"5. Принудительный запуск logrotate для проверки конфигурации\"
logrotate -f /etc/logrotate.conf 2>&1 | tee -a \"$LOGFILE\"
if [[ \${PIPESTATUS[0]} -eq 0 ]]; then\n    log \"   [SUCCESS] logrotate отработал корректно.\"\nelse\n    log \"   [ERROR] Проблемы при запуске logrotate.\"\nfi

log \"==== Настройка логов завершена: \$(date) ====\"

