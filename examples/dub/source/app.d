module dubconfdump;

import agora.config.Config;

import dyaml.node;

import std.getopt;
import std.meta;
import std.stdio;
import std.traits;
import std.typecons;
import core.thread;

struct DubPackageRecipe
{
    ///
    public string name;

    ///
    public @Optional string description;

    public @Optional string[] authors;

    public @Optional string homepage;

    public @Optional string copyright;

    public @Optional string license;

    public @Optional @Name("-ddoxFilterArgs") string ddoxFilterArgs;

    mixin BuildSettingsMixin!();

    //@converter(&fromArray!(Dependency.fromYAML))
    public @Optional @Key("name") Dependency[] dependencies;

    public @Optional ToolchainRequirements toolchainRequirements;

    public @Optional Configuration[] configurations;

    @Key("name")
    public @Optional SubConfiguration[] subConfigurations;
}

mixin template BuildSettingsMixin ()
{
    // dependencies ?
    public @Optional string systemDependencies;
    public @Optional string targetType;
    public @Optional string targetName;
    public @Optional string targetPath;
    public @Optional string workingDirectory;
    // subConfigurations ?
    public @Optional string[] buildRequirements;
    public @Optional mixin FieldWithSuffixes!(string[], "libs", Suffixes);
    public @Optional mixin FieldWithSuffixes!(string[], "sourceFiles", Suffixes);
    public @Optional string[] sourcePaths;
    public @Optional string[] excludedSourceFiles;
    public @Optional string mainSourceFile;
    public @Optional string[] copyFiles;
    public @Optional string[] extraDependencyFiles;
    public @Optional string[] versions;
    public @Optional string[] debugVersions;
    public @Optional string[] importPaths;
    public @Optional string[] stringImportPaths;
    public @Optional string[] preGenerateCommands;
    public @Optional string[] postGenerateCommands;
    public @Optional string[] preBuildCommands;
    public @Optional string[] postBuildCommands;
    public @Optional string[] preRunCommands;
    public @Optional string[] postRunCommands;
    public @Optional string[] dflags;
    public @Optional mixin FieldWithSuffixes!(string[], "lflags", Suffixes);
}

struct Dependency
{
    public string name;

    public @Name("version") string version_;

    public @Optional string path;

    public bool optional;

    public @Name("default") bool default_ = false;

    public @Optional mixin BuildSettingsMixin!();

    // TODO: Improve exceptions
    // public static Dependency fromYAML (Node node)
    // {
    //     if (node.nodeID == NodeID.scalar)
    //         return Dependency(null, node.as!string);
    //     if (node.nodeID != NodeID.mapping)
    //         throw new Exception("Dependencies should be either a single string or a mapping");
    //     return parseConfig!Dependency(CLIArgs.init, node);
    // }
}

public struct Configuration
{
    public string name;
    public @Optional string[] platforms;

    public @Optional mixin BuildSettingsMixin!();
}

public struct SubConfiguration
{
    public string name;
}

private struct ToolchainRequirements
{
    public string dub;
    public string dmd;
    public string ldc;
    public string gdc;
    public string frontend;
}

private template fromArray (alias Func)
{
    public auto fromArray (Node node)
    {
        if (node.nodeID != NodeID.mapping)
            throw new Exception("Expected node to be a mapping, not a: " ~ node.nodeTypeString());
        ReturnType!(Func)[] result;
        foreach (Node key, Node value; node)
        {
            result ~= Func(value);
            result[$-1].name = key.as!string;
        }
        return result;
    }
}

public mixin template FieldWithSuffixes(Type, string name, Suffixes...)
{
    mixin("Type " ~ name ~ ";");
    static foreach (S; Suffixes)
        mixin(`@Name("` ~ name ~ `-` ~ S ~ `") Type ` ~ name ~ `_` ~ S ~ `;`);
}

private alias Suffixes = AliasSeq!(
    `linux`, `posix`, `windows`, `osx`,
);

int main (string[] args)
{
    CLIArgs clargs;
    auto helpInformation = clargs.parse(args);
    if (helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Print the content of a dub.json file",
            helpInformation.options);
        return 0; // Not an error, so exit normally
    }

    // `parseConfigSimple` will print to `stderr` if an error happened
    auto configN = clargs.parseConfigFileSimple!DubPackageRecipe();
    if (configN.isNull())
        return 1;

    writeln("Configuration file ", clargs.config_path, " successfully parsed:");
    writeln(configN.get());
    return 0;
}
