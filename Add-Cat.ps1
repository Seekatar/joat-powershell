

$body = @{name="jim";type="mutt";age="54"}

Invoke-RestMethod -Uri http://192.168.1.107:3002/pets/dogs -Body (ConvertTo-Json $body) -Method POST -ContentType 'application/json'