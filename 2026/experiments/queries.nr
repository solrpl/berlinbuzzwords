#%%vespa
# Search for movies
POST /search
{
  "yql": "select * from movie where true"
}
#%%vespa
# Search for rating
POST /search
{
  "yql": "select * from rating where true"
}
#%%vespa
# Search for tags
POST /search
{
  "yql": "select * from tag where true"
}
#%%vespa
# Grouping try #1
POST /search
{
  "yql": "select * from movie where true",
  "grouping": [
    { "all": { "group": "genres", "each": { "output": "count()" } } },
    { "all": { "group": "year",   "each": { "output": "count()" } } }
  ]
}
#%%vespa
# Grouping with pipes
POST /search
{
  "yql": "select * from movie where true limit 0 | all(group(genres) max(20) order(-count()) each(output(count()))) | all(group(year) max(30) order(-count()) each(output(count()))) | all(group(fixedwidth(year,10)) order(-count()) each(output(count())))"
}
#%%vespa
# Grouping with pipes year sorted via value
POST /search
{
  "yql": "select * from movie where true limit 0 | all(group(genres) max(20) order(-count()) each(output(count()))) | all(group(year) max(30) order(min(year)) each(output(count()))) | all(group(fixedwidth(year,10)) order(-count()) each(output(count())))"
}