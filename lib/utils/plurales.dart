/// "1 póliza" / "3 pólizas": plural real en vez de "póliza(s)".
String plural(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';

/// Solo la palabra, sin el número ("póliza" / "pólizas").
String palabraPlural(int n, String singular, String plural) =>
    n == 1 ? singular : plural;
