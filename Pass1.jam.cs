using System.Collections.Generic;
using JamSharp.Runtime;
using static JamSharp.Runtime.BuiltinRules;
using NiceIO;
using Projects.Jam;

class Pass1 : ConvertedJamFile
{
    internal static void TopLevel()
    {
        Jamrules.InitializeCurrentDir();
        UnpackBuildsZip.Initialize();
        GenerateUnityConfigure.TopLevel();
        Depends("Pass1", "AlwaysZips");
        Depends("Pass1", new JamList((IEnumerable<NPath>)GenerateUnityConfigure.GeneratedHeaders));
    }
}
