#!/bin/bash
# Скрипт настройки логов:
# - Ежедневная ротация логов с хранением за 7 дней.
# - Оптимизация конфигураций logrotate.
# - Настройка systemd-journald.
# - Создание cron-задачи для очистки старых логов.
#
# Логи работы данного скрипта будут записаны в файле deploy_project.log в корне проекта.

LOGFILE="$(dirname "$0")/../../../deploy_project.log"

# Функция логирования с меткой времени
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Проверка, что скрипт запущен от root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Скрипт должен запускаться от root!" 1>&2
  exit 1
fi

log "==== Начало настройки логов: $(date) ===="

# 1. Обновление глобального файла logrotate.conf
log "1. Обновление /etc/logrotate.conf для ежедневной ротации с хранением 7 дней"
cat <<'EOF' > /etc/logrotate.conf
daily
rotate 7
create
dateext
compress
include /etc/logrotate.d
EOF
if [ $? -eq 0 ]; then
  log "   [SUCCESS] /etc/logrotate.conf обновлён."
else
  log "   [ERROR] Не удалось обновить /etc/logrotate.conf."
fi

# 2. Оптимизация файлов в /etc/logrotate.d/
log "2. Оптимизация файлов в /etc/logrotate.d/ для ежедневной ротации"
for file in /etc/logrotate.d/*; do
  if [ -f "$file" ]; then
    log "   Обработка файла: $file"
    sed -i -E 's/(weekly|monthly)/daily/g' "$file"
    sed -i -E 's/rotate[[:space:]]+[0-9]+/rotate 7/g' "$file"
    sed -i -E 's/^#(compress)/\1/g' "$file"
    if ! grep -q "compress" "$file"; then
      sed -i '/create/ a compress' "$file"
    fi
    if [ $? -eq 0 ]; then
      log "      [SUCCESS] Файл $file обработан."
    else
      log "      [ERROR] Проблема при обработке файла $file."
    fi
  fi
done

# 3. Настройка systemd-journald
if systemctl --version &>/dev/null; then
  log "3. Настройка systemd-journald (/etc/systemd/journald.conf)"
  cat <<'EOF' > /etc/systemd/journald.conf
[Journal]
SystemMaxUse=100M
SystemKeepFree=50M
SystemMaxFileSize=25M
MaxRetentionSec=604800
EOF
  if [ $? -eq 0 ]; then
    log "   [SUCCESS] /etc/systemd/journald.conf обновлён."
    systemctl restart systemd-journald
    if [ $? -eq 0 ]; then
      log "   [SUCCESS] systemd-journald перезапущен."
    else
      log "   [ERROR] Не удалось перезапустить systemd-journald."
    fi
  else
    log "   [ERROR] Не удалось обновить /etc/systemd/journald.conf."
  fi
else
  log "   [INFO] systemctl не найден, пропускаем настройку journald."
fi

# 4. Создание cron-задачи для очистки файлов старше 7 дней
log "4. Создание cron-задачи для очистки файлов старше 7 дней (/etc/cron.daily/clean_old_logs)"
cat <<'EOF' > /etc/cron.daily/clean_old_logs
#!/bin/bash
find /var/log -type f -name "*.log.*" -mtime +7 -delete
find /tmp -type f -mtime +7 -delete
EOF
chmod +x /etc/cron.daily/clean_old_logs
if [ $? -eq 0 ]; then
  log "   [SUCCESS] Cron-задача создана."
else
  log "   [ERROR] Не удалось создать cron-задачу."
fi

# 5. Принудительный запуск logrotate для проверки конфигурации
log "5. Принудительный запуск logrotate для проверки конфигурации"
logrotate -f /etc/logrotate.conf 2>&1 | tee -a "$LOGFILE"
rc=$?
if [ $rc -eq 0 ]; then
  log "   [SUCCESS] logrotate отработал корректно."
else
  log "[WARNING] logrotate завершился с кодом $rc. Некоторые ошибки (например, существующие backup-файлы) можно игнорировать."
fi

log "==== Настройка логов завершена: $(date) ===="

