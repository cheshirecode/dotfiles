# projects/

Map-of-content (MOC) pages, one per `project:` slug. Each renders via Dataview the active + recently-archived tasks for that project.

These pages are derivative — they read from `people/<ldap>/{active,archive}/<slug>.md` frontmatter at view time. To add a new project page:

```bash
cp projects/media-pipeline.md projects/<new-project>.md
sed -i '' 's/media-pipeline/<new-project>/g' projects/<new-project>.md
```

Or just let the next `bin/lint.sh --suggest` (planned) catch the missing MOC.

The authoritative project list is `awk '/^project:/{print $2}' people/*/active/*.md people/*/archive/*.md | sort -u`.
