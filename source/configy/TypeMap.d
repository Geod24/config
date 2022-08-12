/*******************************************************************************

    Templates meant to guide Configy with reading complex types

    As Configy aims to take arbitrarily complex types, perhaps some which aren't
    under the user control (e.g. standard library), we need to expose a way to
    guide Configy in the convertion without having to wrap every single types.

    Additionally, we want to minimize compile time impact on the user:
    `parseConfig` is usually the expensive function to compile, as it does all
    the introspection / code generation. Having type maps ensure that the cost
    stay localized to `parseConfig` and doesn't "spill" into the types,
    which it would if the types implemented, e.g. a method called `fromYAML`.

    Copyright:
        Copyright (c) 2019-2022 BOSAGORA Foundation
        All rights reserved.

    License:
        MIT License. See LICENSE for details.

*******************************************************************************/

module configy.TypeMap;

import configy.Attributes;
import configy.Exceptions;
import configy.FieldRef;
import configy.Read;

import dyaml.node;

import std.traits;

import core.time;

/// The interface provided as argument to client code
public final class ConfigParser (alias TypeMap)
{
    private Node node_;
    private string path_;
    private const(Context) context_;

    /// Constructor
    package this (Node n, string p, const Context c)
        scope @safe pure nothrow @nogc
    {
        this.node_ = n;
        this.path_ = p;
        this.context_ = c;
    }

    /// Allow to parse a type as another one
    public final auto parseAs (OtherType)
        (auto ref OtherType defaultValue = OtherType.init)
    {
        alias TypeFieldRef = StructFieldRef!OtherType;
        return this.node().parseField!(StructFieldRef!OtherType, TypeMap)(
            this.path(), defaultValue, this.context());
    }

    /// Returns: The D-YAML `Node` currently being parsed
    public final inout(Node) node () inout @safe pure nothrow @nogc
    {
        return this.node_;
    }

    /// Returns: The symbolic path we are currently at,
    /// for example `root.arr[3].hasmap[name]`.
    public final string path () const @safe pure nothrow @nogc
    {
        return this.path_;
    }

    /// Should only be used internally
    protected final const(Context) context () const @safe pure nothrow @nogc
    {
        return this.context_;
    }
}

/// The default TypeMap used by Configy
public template DefaultTypeMap (T)
{
    static if (is(immutable(T) == immutable(Duration)))
        alias DefaultTypeMap = parseDuration;
}

/// An empty / null type map
public template EmptyTypeMap (T) {}

/// A catch-all TypeMap, used for testing predicates as it short circuits instantiation
package template AnyTypeMap (T) {
    T AnyTypeMap (alias TM) (scope ConfigParser!TM parser)
    {
        return T.init;
    }
}
private alias AnyParser = ConfigParser!AnyTypeMap;

/// Used by read to check a TypeMap
public template hasEntryFor (alias TM, T)
{
    // The typemap should yield a template, e.g. `T function(alias TM)(ConfigParser!TM)`
    public enum hasEntryFor = is(typeof(TM!(T)(AnyParser.init)));
}

/// Utility to add a function to a TypeMap
public template AddEntry (alias TM, Type, alias Func)
{
    static if (!is(typeof(Func!AnyTypeMap)))
    {
        pragma(msg, "============================================================");
        pragma(msg, "Cannot instantiate `", Func.stringof,
               "` with a catch-all typemap, make sure it is a function ",
                  "accepting an `alias` template parameter");
        pragma(msg, "Compilation error of your function may follow:");
        pragma(msg, "============================================================");
        private alias ShowErrors = typeof(Func!AnyTypeMap);
    }
    else
    {
        private alias FuncInst = Func!AnyTypeMap;

        static assert (isSomeFunction!(typeof(FuncInst)),
                       "Template instance of `" ~ Func.stringof ~ "` of type `" ~
                       typeof(FuncInst).stringof ~ "` is not a function");
        static assert (is(typeof(FuncInst(AnyParser.init))),
                       "Function `" ~ Func.stringof ~ "` of type `" ~
                       typeof(FuncInst).stringof ~ "` cannot be called with a `" ~
                       AnyParser.stringof ~ "` as unique function argument");
        static assert (is(typeof(FuncInst(AnyParser.init)) : Type),
                       "Result of function `" ~ Func.stringof ~ "` of type `" ~
                       typeof(FuncInst).stringof ~
                       "` does not implicitly converts to `" ~
                       Type.stringof ~ "`");
    }

    template Result (T)
    {
        static if (is(immutable(T) == immutable(Type)))
            alias Result = Func;
        else
            alias Result = TM!T;
    }

    alias AddEntry = Result;
}

unittest
{
    static struct AnyStruct {}

    static assert(hasEntryFor!(DefaultTypeMap, Duration));

    static assert(!hasEntryFor!(EmptyTypeMap, Duration));
    static assert(!hasEntryFor!(EmptyTypeMap, AnyStruct));

    static assert(hasEntryFor!(AnyTypeMap, Duration));
    static assert(hasEntryFor!(AnyTypeMap, AnyStruct));

    alias NewTypeMap = AddEntry!(EmptyTypeMap, Duration, parseDuration);
    static assert(hasEntryFor!(NewTypeMap, Duration));
}

/// A method to get a Duration from a YAML node, used by default
public Duration parseDuration (alias TM) (scope ConfigParser!TM parser)
{
    if (parser.node.nodeID != NodeID.mapping)
        throw new DurationTypeConfigException(parser.node, parser.path);
    return parser.parseAs!(DurationMapping)().opCast!Duration;
}

/// Allows us to reuse parseMapping and strict parsing
private struct DurationMapping
{
    public SetInfo!long weeks;
    public SetInfo!long days;
    public SetInfo!long hours;
    public SetInfo!long minutes;
    public SetInfo!long seconds;
    public SetInfo!long msecs;
    public SetInfo!long usecs;
    public SetInfo!long hnsecs;
    public SetInfo!long nsecs;

    private static DurationMapping make (Duration def) @safe pure nothrow @nogc
    {
        typeof(return) result;
        auto fullSplit = def.split();
        result.weeks = SetInfo!long(fullSplit.weeks, fullSplit.weeks != 0);
        result.days = SetInfo!long(fullSplit.days, fullSplit.days != 0);
        result.hours = SetInfo!long(fullSplit.hours, fullSplit.hours != 0);
        result.minutes = SetInfo!long(fullSplit.minutes, fullSplit.minutes != 0);
        result.seconds = SetInfo!long(fullSplit.seconds, fullSplit.seconds != 0);
        result.msecs = SetInfo!long(fullSplit.msecs, fullSplit.msecs != 0);
        result.usecs = SetInfo!long(fullSplit.usecs, fullSplit.usecs != 0);
        result.hnsecs = SetInfo!long(fullSplit.hnsecs, fullSplit.hnsecs != 0);
        // nsecs is ignored by split as it's not representable in `Duration`
        return result;
    }

    ///
    public void validate () const @safe
    {
        // That check should never fail, as the YAML parser would error out,
        // but better be safe than sorry.
        foreach (field; this.tupleof)
            if (field.set)
                return;

        throw new Exception(
            "Expected at least one of the components (weeks, days, hours, " ~
            "minutes, seconds, msecs, usecs, hnsecs, nsecs) to be set");
    }

    ///  Allow conversion to a `Duration`
    public Duration opCast (T : Duration) () const scope @safe pure nothrow @nogc
    {
        return core.time.weeks(this.weeks) + core.time.days(this.days) +
            core.time.hours(this.hours) + core.time.minutes(this.minutes) +
            core.time.seconds(this.seconds) + core.time.msecs(this.msecs) +
            core.time.usecs(this.usecs) + core.time.hnsecs(this.hnsecs) +
            core.time.nsecs(this.nsecs);
    }
}
