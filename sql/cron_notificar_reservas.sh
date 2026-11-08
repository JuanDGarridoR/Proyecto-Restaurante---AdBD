#!/bin/bash
# Cron job: Detectar y notificar reservas próximas (cada 5 minutos)
# Base de datos: restaurante en PostgreSQL
/usr/bin/psql -h localhost -U estudiante -d restaurante -c "SELECT fn_notificar_reservas_proximas(30);" >/dev/null 2>&1
