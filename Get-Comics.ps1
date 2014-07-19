<#
.Synopsis
    Build a little html page of comics

.Description
    Builds and launches the we page.  Note that GoComics does not have a rigorous naming
	convention, so there is code here to handle some of the exceptions that I've found.

.Parameter myName
    name for title

.Parameter comics
    string array of comic names from GoComics.com, additionally, Zits or Dilbert

#>
[CmdletBinding()]
param(
[string] $myName = "Jim",
[string[]] $comics  = @("Dilbert","Zits","Kit 'N' Carlyle", "For Better or For Worse", "Non Sequitur", "Pearls Before Swine", "Off the Mark", "Stone Soup", "The Argyle Sweater")
)

try
{
    # need system.web for encoding
    $wc = New-Object System.Net.WebClient
    Add-Type -assemblyName System.Web

    # helper function to get the comic and build the link
    function getComic( $name, $url, $searchRegEx, $matchRegEx )
    {
        $myDoc = ""

        Write-Verbose "Downloading $url"
        $x = [System.Web.HttpUtility]::HtmlDecode($wc.DownloadString($url)) -split "<"
        Write-Debug $x.ToString()

        $y = $x | where { $_ -match $searchRegEx } 
        Write-Verbose "Url should be here: $y"

        if ( $y -match $matchRegEx )
        {
            $src = $matches[1]
            if ($src -notlike "http*")
            {
                $src = $url + $src
            }
            Write-Verbose "Match is $src"
            $myDoc += "<div class=`"cartoon`"><h2><a href=`"$([System.Web.HttpUtility]::HtmlEncode($url))`">$c</a></h2>`n"
            $myDoc += "<img src=`"$src`"/><br></div>`n"
            Write-Host "Found $c"
        }
        else
        {
            Write-Warning "Didn't find url match for `"$c`" in $y"
        }

        return $myDoc

    }

    # prep the html
    $doc = "<html>`n"
    $style = @"
    <style>
    h1 { font-family:sans-serif; font-style:italic; color:#505050}
    hr { color:darkblue;strokewidth=3 }
    img { align:center }
    a {font-family:sans-serif; text-decoration:none; font-style:italic; color:#505050}
    .cartoon { float:left; border:solid 2px; border-radius:6px; border-color:#808080; margin:5px 5px 50px 5px; padding:5px; width:auto; box-shadow: 10px 10px 15px #888888}
    </style>
"@
    $doc += $style
    $doc += "<h1>$myName's Comics</h1>"

    # 

    foreach ( $c in $comics )
    {
        if ( $c -eq "Zits" )
        {
            $doc += getComic $c "http://zitscomics.com/" "src=`"(.*content\.php\?file=[^`"]+)" "src=`"(.*content\.php\?file=[^`"]+)"

        }
        elseif ( $c -eq "Dilbert" )
        {
            $doc += getComic $c "http://dilbert.com/" "alt=`"The Official Dilbert" "src=`"([^`"]+)"
        }
        else # go comic
        {
            $baseUrl = "http://www.gocomics.com/"
            # Kit 'N' -> Kit and
            $doc += getComic $c $($baseUrl+$c.Replace(" ","").Replace("'N'","and")) "alt=`"\s*$c\s*`"" '(http://[^"]*)'
        }
    }

    # finish up the doc
    $doc += "</html>`n"
    $doc > "$PWD\comics.html"
    "$PWD\comics.html"
    & "$PWD\comics.html"
}
catch
{
    Write-Error "Exception was $_`n$_.ScriptStackTrace"
}