# ДЗ 5 «Инженерия данных»: управление ресурсами в Kubernetes

**Вариант 10 — Аналитики.** Голубева Мария Сергеевна, J3313.

Отчёт: [`report/report.pdf`](report/report.pdf)

Расчёт пар навыков из [ДЗ 3](https://github.com/masha363/data-engineering-hw3) собран в образ и запущен в кластере kind
(Kubernetes v1.37.0, один узел, 8 CPU, 4 ГБ памяти Docker Desktop) как задания с заявками и пределами ресурсов.
Хранилище RustFS из ДЗ 2 перенесено внутрь кластера, расчёт выполнен параллельными заданиями по частям объекта.

## Результаты

| что | итог | журнал |
|---|---|---|
| предел памяти 64Mi | `OOMKilled`, код 137 | `logs/describe_pod_skills-oom.txt`, `logs/step2_memory.log` |
| замер пика | RSS 154,9 МБ | `logs/job_skills-measure.log` |
| подобранный предел | requests 160Mi, limits 208Mi (пик × 1,25), задание успешно | `k8s/03-job-fit.yaml`, `logs/job_skills-fit.log` |
| RustFS в кластере | StatefulSet, 4 тома, бакет `hh-lake` | `k8s/10-rustfs.yaml`, `logs/step3_s3.log` |
| расчёт по 4 частям | Indexed Job, 4 пода параллельно, слияние совпало с ДЗ 3 | `logs/job_skills-parts.log`, `logs/job_skills-merge.log` |
| нехватка CPU | `Pending`: `Insufficient cpu`, запуск после освобождения | `logs/events_cpu-waiter.txt` |
| вытеснение | `cpu-high` вытеснил `cpu-low`: `Preempted by pod …` | `logs/events_preemption.txt` |
| квота пространства имён | под без ресурсов отклонён; 2 CPU при квоте 1 — `exceeded quota`; 4 части по 400m шли по 2 | `logs/step5_quota.log`, `logs/events_quota.txt` |

Топ-10 пар навыков (совпадает с ДЗ 3, а также все 157 717 пар построчно):

| # | пара | вакансий |
|---|---|---|
| 1 | BPMN + UML | 3880 |
| 2 | BPMN + SQL | 2966 |
| 3 | SQL + UML | 2681 |
| 4 | Python + SQL | 2671 |
| 5 | Анализ данных + Аналитическое мышление | 2507 |
| 6 | SQL + Системный анализ | 2442 |
| 7 | BPMN + Системный анализ | 2238 |
| 8 | Аналитическое мышление + Работа с большим объемом информации | 2236 |
| 9 | UML + Системный анализ | 2055 |
| 10 | SQL + Аналитическое мышление | 2050 |

## Структура

| путь | что это |
|---|---|
| `app/Dockerfile`, `app/skills.py` | образ и программа: режимы `local`, `upload`, `part`, `merge` |
| `app/hw3/` | контрольные числа и таблицы k1/k2 из ДЗ 3 для сверки |
| `kind-config.yaml` | кластер kind, папка `data/` смонтирована в узел как `/hostdata` |
| `k8s/0*` | задания с пределом 64Mi, замер и подобранный предел |
| `k8s/1*` | RustFS (StatefulSet + Service + Secret), загрузка, части, слияние |
| `k8s/2*` | классы приоритета и задания для опытов с CPU |
| `k8s/3*` | квота пространства имён `hw5-quota` и задания под ней |
| `scripts/step*.sh` | шаги работы, каждый пишет журнал в `logs/` |
| `logs/` | журналы шагов, заданий, подов, события, `describe` |
| `results/` | подобранный предел, план CPU, итог слияния |

## Запуск

```bash
brew install kind
mkdir -p data && cp <путь>/hh_analysts_2024.csv data/
bash scripts/step1_cluster.sh
bash scripts/step2_memory.sh
bash scripts/step3_s3.sh
bash scripts/step4_priority.sh
bash scripts/step5_quota.sh
```
