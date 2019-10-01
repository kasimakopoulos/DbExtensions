param(
   [Parameter(Mandatory=$true, Position=0)][string]$ProjectName,
   [Parameter(Mandatory=$true)][Version]$AssemblyVersion,
   [Parameter(Mandatory=$true)][Version]$PackageVersion,
   [Parameter()][string]$PreRelease
)

$ErrorActionPreference = "Stop"
Push-Location (Split-Path $script:MyInvocation.MyCommand.Path)

$solutionPath = Resolve-Path ..\..
$nuget = Join-Path $solutionPath .nuget\nuget.exe
$configuration = "Release"

function script:ProjectPath([string]$projName) {
   Resolve-Path $solutionPath\src\$projName
}

function script:ProjectFile([string]$projName) {
   $projPath = ProjectPath $projName
   return "$projPath\$projName.csproj"
}

function script:NuSpec {

   $targetFx = $projDoc.DocumentElement.SelectSingleNode("*/*[local-name() = 'TargetFrameworkVersion']").InnerText
   $targetFxMoniker = "net" + $targetFx.Substring(1).Replace(".", "")

   "<package xmlns='http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd'>"
      "<metadata>"
         "<id>$projName</id>"
         "<version>$pkgVersion</version>"
         "<authors>$($notice.authors)</authors>"
         "<license type='expression'>$($notice.license.name)</license>"
         "<projectUrl>$($notice.website)</projectUrl>"
         "<copyright>$($notice.copyright)</copyright>"
         "<iconUrl>$($notice.website)nuget/icon.png</iconUrl>"
         "<repository type='git' url='https://github.com/maxtoroq/DbExtensions' commit='$(git rev-parse HEAD)'/>"
         "<releaseNotes>For a list of changes see $($notice.website)docs/changes.html</releaseNotes>"

   if ($projName -eq "DbExtensions") {

      "<description>DbExtensions is a data-access framework with a strong focus on query composition, granularity and code aesthetics. It supports both POCO and dynamic (untyped) mapping.</description>"
      "<tags>ado.net orm micro-orm</tags>"

      "<frameworkAssemblies>"
         "<frameworkAssembly assemblyName='System.Core' targetFramework='$targetFxMoniker'/>"
         "<frameworkAssembly assemblyName='System.Data' targetFramework='$targetFxMoniker'/>"
      "</frameworkAssemblies>"
   }

   "</metadata>"

   "<files>"
      "<file src='$solutionPath\LICENSE.txt'/>"
      "<file src='$solutionPath\NOTICE.xml'/>"
      "<file src='$projPath\bin\$configuration\$projName.dll' target='lib\$targetFxMoniker'/>"
      "<file src='$projPath\bin\$configuration\$projName.pdb' target='lib\$targetFxMoniker'/>"
      "<file src='$solutionPath\build\docs\api\xml\$projName.xml' target='lib\$targetFxMoniker'/>"

   if ($projName -eq "DbExtensions") {

      $coreTargetFxMoniker = $coreProjDoc.DocumentElement.SelectSingleNode("*/*[local-name() = 'TargetFramework']").InnerText

      "<file src='$coreProjPath\bin\$configuration\$coreTargetFxMoniker\$projName.dll' target='lib\$coreTargetFxMoniker'/>"
      "<file src='$coreProjPath\bin\$configuration\$coreTargetFxMoniker\$projName.pdb' target='lib\$coreTargetFxMoniker'/>"
      "<file src='$solutionPath\build\docs\api\xml\$projName.xml' target='lib\$coreTargetFxMoniker'/>"

      $stdTargetFxMoniker = $stdProjDoc.DocumentElement.SelectSingleNode("*/*[local-name() = 'TargetFramework']").InnerText

      "<file src='$stdProjPath\bin\Release\$stdTargetFxMoniker\$projName.dll' target='lib\$stdTargetFxMoniker'/>"
      "<file src='$stdProjPath\bin\Release\$stdTargetFxMoniker\$projName.pdb' target='lib\$stdTargetFxMoniker'/>"
      "<file src='$solutionPath\build\docs\api\xml\$projName.xml' target='lib\$stdTargetFxMoniker'/>"
   }

   "</files>"

   "</package>"
}

function script:Build([xml]$projDoc, [string]$projFile) {

   ## Add signature to project file

   $signatureXml = "<ItemGroup xmlns='$($projDoc.DocumentElement.NamespaceURI)'>
      <Compile Include='$signaturePath'>
         <Link>AssemblySignature.cs</Link>
      </Compile>
   </ItemGroup>"

   $signatureReader = [Xml.XmlReader]::Create((New-Object IO.StringReader $signatureXml))
   $signatureReader.MoveToContent() | Out-Null

   $signatureNode = $projDoc.ReadNode($signatureReader)

   $projDoc.DocumentElement.AppendChild($signatureNode) | Out-Null
   $signatureNode.RemoveAttribute("xmlns")

   $projDoc.Save($projFile)

   ## Build project and remove signature

   MSBuild $projFile /p:Configuration=$configuration /p:BuildProjectReferences=false

   $projDoc.DocumentElement.RemoveChild($signatureNode) | Out-Null
   $projDoc.Save($projFile)
}

function script:NuPack([string]$projName) {

   $pkgVersion = "$PackageVersion$(if ($PreRelease) { ""-$PreRelease"" } else { $null })"
   $projPath = Resolve-Path $solutionPath\src\$projName
   $projFile = "$projPath\$projName.csproj"

   [xml]$noticeDoc = Get-Content $solutionPath\NOTICE.xml
   $notice = $noticeDoc.DocumentElement

   if (-not (Test-Path temp -PathType Container)) {
      md temp | Out-Null
   }

   if (-not (Test-Path temp\$projName -PathType Container)) {
      md temp\$projName | Out-Null
   }

   if (-not (Test-Path nupkg -PathType Container)) {
      md nupkg | Out-Null
   }

   $tempPath = Resolve-Path temp\$projName
   $outputPath = Resolve-Path nupkg

   ## Read project file

   $projDoc = New-Object Xml.XmlDocument
   $projDoc.PreserveWhitespace = $true
   $projDoc.Load($projFile)

   if ($projName -eq "DbExtensions") {

      $coreProjName = "$($projName).netcore"
      $coreProjPath = Resolve-Path $solutionPath\src\$coreProjName
      $coreProjFile = "$coreProjPath\$coreProjName.csproj"

      $coreProjDoc = New-Object Xml.XmlDocument
      $coreProjDoc.PreserveWhitespace = $true
      $coreProjDoc.Load($coreProjFile)

      $stdProjName = "$($projName).netstd"
      $stdProjPath = Resolve-Path $solutionPath\src\$stdProjName
      $stdProjFile = "$stdProjPath\$stdProjName.csproj"

      $stdProjDoc = New-Object Xml.XmlDocument
      $stdProjDoc.PreserveWhitespace = $true
      $stdProjDoc.Load($stdProjFile)
   }

   ## Create assembly signature file

   $signaturePath = "$tempPath\AssemblySignature.cs"
   $signature = @"
using System;
using System.Reflection;

[assembly: AssemblyProduct("$($notice.work)")]
[assembly: AssemblyCompany("$($notice.website)")]
[assembly: AssemblyCopyright("$($notice.copyright)")]
[assembly: AssemblyVersion("$AssemblyVersion")]
[assembly: AssemblyFileVersion("$PackageVersion")]
[assembly: AssemblyInformationalVersion("$pkgVersion")]
"@

   $signature | Out-File $signaturePath -Encoding utf8

   ## Build project

   Build $projDoc $projFile

   if ($projName -eq "DbExtensions") {
      Build $coreProjDoc $coreProjFile
      Build $stdProjDoc $stdProjFile
   }

   ## Create nuspec using info from project file and notice

   $nuspecPath = "$tempPath\$projName.nuspec"

   NuSpec | Out-File $nuspecPath -Encoding utf8

   ## Create package

   &$nuget pack $nuspecPath -OutputDirectory $outputPath
}

try {

   ..\ensure-nuget.ps1
   ..\restore-packages.ps1

   if ($ProjectName -eq '*') {
      NuPack DbExtensions
   } else {
      NuPack $ProjectName
   }

} finally {
   Pop-Location
}
