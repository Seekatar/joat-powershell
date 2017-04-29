
# 429 is thorttle raise
# else > 400 raise

<<<<<<< HEAD
$baseUri = "http://localhost:8081" 
$baseUri = "http://io.adafruit.com/api"
$aioKey = '3a520c87c4ac836552c6c2703abebdfbb32327ad'
$feedName = "Welcome%20Feed" # "welcome-feed"
=======
$baseUri = "https://io.adafruit.com/api"
$aioKey = 'zzzzzzzzzzzzzzzzzzzzzzzz'
$feedName = "Welcome Feed"
>>>>>>> 449506729141ee27792dd415b48d29f4b6d1d7e8
$groupKey = "my-feeds"

# groups 

$groups = Invoke-RestMethod -Uri "$baseUri/groups set" -Method Get -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 
$groups | ft -a
Invoke-RestMethod -Uri "$baseUri/groups/$groupKey" -Method Get -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 

if ( $addAndDeleteGroup )
{
    # add a group, at least name should be set
    $value = ConvertTo-Json -InputObject @{name='Seekatar test group';description='this is a test'}
    Invoke-RestMethod -Method Post -Uri "$baseUri/groups" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} -Body $value 

    # delete a feed, can use name, id
    $newGroup = 'seekatar-test-group'
    Invoke-RestMethod -Method Delete -Uri "$baseUri/groups/$newGroup" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 
}

# specific to a group

# send data, create new group, doesn't seem to work
$value = ConvertTo-Json -InputObject @{value=@{$feedName=999}}
Invoke-RestMethod -Method Post -Uri "$baseUri/groups/$groupKey/send" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} -Body $value 

# get last
Invoke-RestMethod -Method Get -Uri "$baseUri/groups/$groupKey/last" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 

# get next unread
Invoke-RestMethod -Method Get -Uri "$baseUri/groups/$groupKey/next" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 

# get previous unread
Invoke-RestMethod -Method Get -Uri "$baseUri/groups/$groupKey/previous" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 


# get feeds, can specify /feedName
$feeds = Invoke-RestMethod -Uri "$baseUri/feeds" -Method Get -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 
$feeds | ft -a
Invoke-RestMethod -Uri "$baseUri/feeds/$feedName" -Method Get -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey}

if ( $addAndDeleteFeed )
{
    # add a feed, at least name should be set
    $value = ConvertTo-Json -InputObject @{name='Seekatar test feed';description='this is a test'}
    Invoke-RestMethod -Method Post -Uri "$baseUri/feeds" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} -Body $value 

    # delete a feed, can use name, id
    $newFeed = 'seekatar-test-feed'
    Invoke-RestMethod -Method Delete -Uri "$baseUri/feeds/$newFeed" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 
}

# specific to a feed

# send data, creating new feed
$value = ConvertTo-Json -InputObject @{value=123}
Invoke-RestMethod -Method Post -Uri "$baseUri/feeds/$feedName/data/send" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} -Body $value 

# get last
Invoke-RestMethod -Method Get -Uri "$baseUri/feeds/$feedName/data/last" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 

# get next unread
Invoke-RestMethod -Method Get -Uri "$baseUri/feeds/$feedName/data/next" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 

# get previous unread
Invoke-RestMethod -Method Get -Uri "$baseUri/feeds/$feedName/data/previous" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 

$data = Invoke-RestMethod -Method Get -Uri "$baseUri/feeds/$feedName/data" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 
$data | ft -a

# get one id
$id = 389690834
Invoke-RestMethod -Method Get -Uri "$baseUri/feeds/$feedName/data/$id" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey}

$result = Invoke-WebRequest -Method Get -Uri "$baseUri/feeds/$feedName/data/$id" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 

$i = 12
# new row
foreach ( $i in 123..456)
{
    $value = ConvertTo-Json -InputObject @{value=$i;lat=1;lon=2;ele=3}
    Invoke-RestMethod -Method Post -Uri "$baseUri/feeds/$feedName/data/send" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} -Body $value 
}

# delete row
$id = 388874471
Invoke-RestMethod -Method Delete -Uri "$baseUri/feeds/$feedName/data/$id" -ContentType 'application/json' -Headers @{'X-AIO-Key'=$aioKey} 