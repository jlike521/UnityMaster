@ECHO OFF

REM Wrapper script to make running build.pl a little quicker.  Arguments are same
REM as for build.pl
REM
REM ./run           (launches editor)
REM ./run -noUpm    (launches editor with given commandline arguments, multiple arguments are supported)
REM ./run test      (run tests)

set str=%1
IF "%str%" == "" (
	perl build.pl run
) ELSE (
	IF "%str:~0,1%" == "-" (
		IF "%str%" == "--help" (
			perl build.pl %*
		) ELSE (
			perl build.pl run --runArgs="%*"
		)
	) ELSE (
		perl build.pl %*
	)
)
