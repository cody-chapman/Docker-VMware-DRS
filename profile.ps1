Import-Module CustomDRS
If (-not (Test-Path //CustomDRS.db)) {
	Initialize-SQLLite3
	Initialize-CustomDRSDatabase
} else {
	Initialize-SQLLite3        
}
