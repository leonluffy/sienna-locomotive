#Set-PSDebug -Trace 1

$cwd=(Get-Item -Path ".\").FullName

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName Microsoft.VisualBasic

function Unzip {
    param([string]$zipfile, [string]$outpath)

    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

Function InstallDependencies {
    python -m pip install -r requirements.txt
    python setup.py develop
}

Function DynamioRioInstall {

    $dynamorioDir = "dynamorio"
    $dynamorioBase = "DynamoRIO-Windows-7.0.17721-0"

    If ( Test-Path $dynamorioDir ) {
        $dynamorioDir + " already exists "
        return
    }

    $url="https://github.com/DynamoRIO/dynamorio/releases/download/cronbuild-7.0.17721/${dynamorioBase}.zip"

    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls,Tls11,Tls12'
    $client = New-Object System.Net.WebClient

    $zip = $cwd + "\dr.zip"
    "Downloading " + $url
    $client.DownloadFile($url, $zip)
    "Unzipping " + $zip
    Unzip $zip $cwd
    mv $dynamorioBase $dynamorioDir
}

Function Doc {
    $url="http://ftp.stack.nl/pub/users/dimitri/doxygen-1.8.14-setup.exe"
    "Install doxygen from ${url}"
    doxygen Doxyfile.in
}

Function Build {
    taskkill.exe /IM fuzzgoat.exe /F
    taskkill.exe /IM test_application.exe /F
    Push-Location
    InstallDependencies
    DynamioRioInstall

    #if not exist "build" mkdir build
    New-Item -ItemType Directory -Force -Path build
    cd build
    $dynamorioCmake="${cwd}\dynamorio\cmake"
    cmake -G"Visual Studio 15 Win64" "-DDynamoRIO_DIR=${dynamorioCmake}" ..
    cmake --build .
    Pop-Location
}


Function SafeDelete {
    param( [string]$path )

    if ( Test-Path "$path" ) {
        "Deleting ${path}"
        Remove-Item $path -Force -Recurse
    }
}

Function Reconfig {
    taskkill.exe /IM test_application.exe /F
    taskkill.exe /IM server.exe /F
    [Microsoft.VisualBasic.FileIO.FileSystem]::Deletedirectory("$env:APPDATA\Trail of Bits\sl2",'OnlyErrorDialogs','SendToRecycleBin')
}

Function Clean {
    Reconfig
    SafeDelete "build"
    "It's clean!"
}

Function Dep {
    SafeDelete "dr.zip"
    SafeDelete "dynamorio"
}

Function Deploy {
    "Rebuilding Code Files"
    Build

    "Rebuilding Documentation"
    Doc

    "Creating Deploy Directory"
    Remove-Item sl2-deploy -Recurse -ErrorAction Ignore
    mkdir sl2-deploy

    "Creating Binary Directories"
    New-Item sl2-deploy\build\common -Type Directory
    New-Item sl2-deploy\build\corpus\test_application -Type Directory
    New-Item sl2-deploy\build\fuzzer -Type Directory
    New-Item sl2-deploy\build\fuzzgoat -Type Directory
    New-Item sl2-deploy\build\server -Type Directory
    New-Item sl2-deploy\build\tracer -Type Directory
    New-Item sl2-deploy\build\triage -Type Directory
    New-Item sl2-deploy\build\winchecksec -Type Directory
    New-Item sl2-deploy\build\wizard -Type Directory
    New-Item sl2-deploy\pypy -Type Directory

    "Copying Compiled Binaries"
    Copy-Item build\common\Debug sl2-deploy\build\common -Recurse -Force
    Copy-Item build\corpus\test_application\Debug sl2-deploy\build\corpus\test_application -Recurse -Force
    Copy-Item build\fuzzer\Debug sl2-deploy\build\fuzzer -Recurse -Force
    Copy-Item build\fuzzgoat\Debug sl2-deploy\build\fuzzgoat -Recurse -Force
    Copy-Item build\server\Debug sl2-deploy\build\server -Recurse -Force
    Copy-Item build\tracer\Debug sl2-deploy\build\tracer -Recurse -Force
    Copy-Item build\triage\Debug sl2-deploy\build\triage -Recurse -Force
    Copy-Item build\winchecksec\Debug sl2-deploy\build\winchecksec -Recurse -Force
    Copy-Item build\wizard\Debug sl2-deploy\build\wizard -Recurse -Force

    "Copying Documentation"
    New-Item sl2-deploy\doc -Type Directory
    Copy-Item doc\html sl2-deploy\doc -Recurse -Force

    "Copying DynamoRIO"
    Copy-Item -Recurse dynamorio sl2-deploy

    "Copying Python Files"
    Copy-Item sl2 sl2-deploy -Recurse -Force

    "Copying Helper Files"
    Copy-Item deploy\* sl2-deploy
    Copy-Item setup.py sl2-deploy
    Copy-Item README.md sl2-deploy
    Copy-Item requirements.txt sl2-deploy

    $url="https://www.python.org/ftp/python/3.7.0/python-3.7.0-amd64.exe"

    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls,Tls11,Tls12'
    $client = New-Object System.Net.WebClient

    "Downloading Python from " + $url
    $exe = "$cwd\sl2-deploy\python_install.exe"
    $client.DownloadFile($url, $exe)

    "Downloading Python Dependencies"
    python -m pip download -d sl2-deploy\pypy -r requirements.txt

    "Compressing Deployment Archive"
    if (-not (test-path "$env:ProgramFiles\7-Zip\7z.exe")) {throw "$env:ProgramFiles\7-Zip\7z.exe missing"}
    set-alias zip "$env:ProgramFiles\7-Zip\7z.exe"
    zip a -r -mx=9 sl2-deploy.zip sl2-deploy\*
}

Function Help {
    @'
Usage: make1.ps [clean|dep|reconfig|help]

make1.ps without any options will build


clean
    Cleans build directory and configuration (reconfigs)

dep
    Rebuild dependencies

reconfig
    Deletes sl2 directory with run configuration

help
    This info
'@
}


function Regress {
    sl2-test
}

$cmd = $args[0]

switch( $cmd ) {
    "clean"             { Clean }
    "dep"               { Dep }
    "reconfig"          { Reconfig }
    "regress"           { Regress }
    "help"              { Help }
    "doc"               { Doc }
    "deploy"            { Deploy }
    default             { Build }
}
