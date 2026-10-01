import sys
import duckdb

con = duckdb.connect('data/olist.duckdb')
sql = open(sys.argv[1], encoding='utf-8').read()

for stmt in [s.strip() for s in sql.split(';') if s.strip()]:
    res = con.execute(stmt)
    if res.description:
        print(res.fetchdf().to_string(index=False))
        print()
