read -r l1 l5 _ </proc/loadavg
mt=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%d,%d",(t-a)/1024,t/1024}' /proc/meminfo)
dsk=$(df -P / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
up=$(cut -d. -f1 /proc/uptime)
cpus=$(nproc)
cu=$(docker ps -q 2>/dev/null | wc -l)
cx=$(docker ps -aq -f status=exited 2>/dev/null | wc -l)
echo "H|$l1|$l5|$mt|$dsk|$up|$cpus|$cu|$cx"
docker ps --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null | grep -Ei 'postgres|redis|mysql|maria|mongo|minio' | while IFS='|' read -r n img st; do
  v=""
  case "$img" in
    *postgres*)
      v=$(docker exec "$n" sh -c 'psql -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-postgres}" -tAF, -c "select count(*), pg_database_size(current_database()) from pg_stat_activity"' 2>/dev/null | tr -d ' ')
      ;;
    *redis*)
      v=$(docker exec "$n" redis-cli info clients 2>/dev/null | awk -F: '/connected_clients/{gsub(/\r/,"");print $2",0"}')
      ;;
  esac
  case "$st" in *unhealthy*) h=u ;; *healthy*) h=h ;; *) h=- ;; esac
  echo "D|$n|${img%%:*}|${v:--,-}|$h"
done
