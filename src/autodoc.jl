module AutoDoc
using HTTP
using JSON3
using Dates
using DataStructures
using Reexport
using RelocatableFolders

using ..Util: html, recursive_merge
using ..Constants
using ..AppContext: ServerContext, Documenation
using ..Types: TaggedRoute, TaskDefinition, CronDefinition, Nullable, Param, isrequired
using ..Extractors: isextractor, extracttype, isreqparam
using ..Reflection: splitdef

export registerschema, swaggerhtml, redochtml, mergeschema

"""
    mergeschema(route::String, customschema::Dict)

Merge the schema of a specific route
"""
function mergeschema(schema::Dict, route::String, customschema::Dict)
    schema["paths"][route] = recursive_merge(get(schema["paths"], route, Dict()), customschema)
end


"""
    mergeschema(customschema::Dict)

Merge the top-level autogenerated schema with a custom schema
"""
function mergeschema(schema::Dict, customschema::Dict)
    updated_schema = recursive_merge(schema, customschema)
    merge!(schema, updated_schema)
end


"""
Returns the openapi equivalent of each Julia type
"""
function gettype(type::Type)::String
    if type <: Bool
        return "boolean"
    elseif type <: AbstractFloat
        return "number"
    elseif type <: Integer
        return "integer"
    elseif type <: AbstractVector
        return "array"
    elseif type <: String || type == Date || type == DateTime
        return "string"
    elseif isstructtype(type)
        return "object"
    else
        return "string"
    end
end

"""
Returns the specific format type for a given parameter
ex.) DateTime(2022,1,1) => "date-time"
"""
function getformat(type::Type) :: Nullable{String}
    if type <: AbstractFloat
        if type == Float32
            return "float"
        elseif type == Float64
            return "double"
        end
    elseif type <: Integer
        if type == Int32
            return "int32"
        elseif type == Int64
            return "int64"
        end
    elseif type == Date
        return "date"
    elseif type == DateTime
        return "date-time"
    end
    return nothing
end

function getcomponent(name::AbstractString) :: String
    return "#/components/schemas/$name"
end

function getcomponent(t::DataType) :: String
    return getcomponent(string(nameof(t)))
end

function datetime_hint() :: String
    return "Note: Julia's DateTime object does not natively support timezone information. Consider using the TimeZones.jl package for timezone-aware datetime handling."
end

function createparam(p::Param{T}, paramtype::String) :: Dict where {T}

    schema = Dict("type" => gettype(p.type))

    # Add ref if the type is a custom struct
    if schema["type"] == "object"
        schema["\$ref"] = getcomponent(p.type)
    end

    # Add optional format if it's relevant
    format = getformat(p.type)
    if !isnothing(format)
        schema["format"] = format
    end

    # Add default value if it exists
    if p.hasdefault
        schema["default"] = string(p.default)
    end

    # path params are always required
    param_required = paramtype == "path" ? true : isrequired(p)

    param = Dict(
        "in" => paramtype, # path, query, header (where the parameter is located)
        "name" => String(p.name),
        "required" => param_required,
        "schema" => schema
    )

    # Add a string formatting hint & example for DateTime objects
    if p.type <: DateTime 
        param["example"] = example_datetime()
        param["description"] = datetime_hint()
    end

    return param
end

"""
This function helps format the individual parameters for each route in the openapi schema
"""
function formatparam!(params::Vector{Any}, p::Param{T}, paramtype::String) where T
    # Will need to flatten request extrators & append all properties to the schema
    if isextractor(p) && isreqparam(p)
        type = extracttype(p.type)
        info = splitdef(type)
        sig_names = OrderedSet{Symbol}(p.name for p in info.sig)
        for name in sig_names
            push!(params, createparam(info.sig_map[name], paramtype))
        end
    else
        push!(params, createparam(p, paramtype))
    end
end


"""
This function helps format the content object for each route in the openapi schema.

If similar body extractors are used, all schema's are included using an "allOf" relation.
The only exception to this is the text/plain case, which excepts the Body extractor. 
If there are more than one Body extractor, the type defaults to string - since this is 
the only way to represent multiple formats at the same time.
"""
function formatcontent(bodyparams::Vector) :: OrderedDict

    body_refs = Dict{String,Vector{String}}()
    body_types = Dict()

    for p in bodyparams

        inner_type      = p.type |> extracttype
        inner_type_name = inner_type |> nameof |> string
        extractor_name  = p.type |> nameof |> string
        body_types[extractor_name] = gettype(inner_type)

        if !is_custom_struct(inner_type)
            continue
        end

        if !haskey(body_refs, extractor_name)
            body_refs[extractor_name] = []
        end

        body_refs[extractor_name] = vcat(body_refs[extractor_name], getcomponent(inner_type_name))
    end

    jsonschema = collectschemarefs(body_refs, ["Json", "JsonFragment"])
    jsonschema = merge(jsonschema, Dict("type" => "object"))

    # The schema type for text/plain can vary unlike the other types
    textschema = collectschemarefs(body_refs, ["Body"])
    # If there are multiple Body extractors, default to string type
    textschema_type = length(textschema["allOf"]) > 1 ? "string" : get(body_types, "Body", "string")
    textschema = merge(textschema, Dict("type" => textschema_type))

    formschema = collectschemarefs(body_refs, ["Form"])
    formschema = merge(formschema, Dict("type" => "object"))

    content = Dict(
        "application/json" => Dict(
            "schema" => jsonschema
        ),
        "text/plain" => Dict(
            "schema" => textschema
        ),
        "application/x-www-form-urlencoded" => Dict(
            "schema" => formschema
        ),
        "application/xml" => Dict(
            "schema" => Dict(
                "type" => "object"
            )
        ),
        "multipart/form-data" => Dict(
            "schema" => Dict(
                "type" => "object",
                "properties" => Dict(
                    "file" => Dict(
                        "type" => "string",
                        "format" => "binary"
                    )
                ),
                "required" => ["file"]
            )
        )
    )

    ##### Add Schemas to this route, with the preferred content type first #####
    ordered_content = OrderedDict()

    if !isempty(jsonschema["allOf"])
        ordered_content["application/json"] = Dict("schema" => jsonschema)
    end

    if !isempty(textschema["allOf"])
        ordered_content["text/plain"] = Dict("schema" => textschema)
    end

    if !isempty(formschema["allOf"])
        ordered_content["application/x-www-form-urlencoded"] = Dict("schema" => formschema)
    end

    # Add all other content types (won't default to these, but they are available)
    for (key, value) in content
        if !haskey(ordered_content, key)
            ordered_content[key] = value
        end
    end

    return ordered_content
end


"""
Used to generate & register schema related for a specific endpoint 
"""
function registerschema(
    docs::Documenation,
    path::String,
    httpmethod::String,
    parameters::Vector,
    queryparams::Vector,
    headers::Vector,
    bodyparams::Vector,
    returntype::Vector)

    ##### Add all the body parameters to the schema #####

    schemas = Dict()
    for p in bodyparams
        inner_type = p.type |> extracttype
        if is_custom_struct(inner_type)
            convertobject!(inner_type, schemas)
        end
    end

    ##### Append the parameter schema for the route #####
    params = []

    for (param_list, location) in [(parameters, "path"), (queryparams, "query"), (headers, "header")]
        for p in param_list
            formatparam!(params, p, location)
        end
    end

    ##### Set the schema for the body parameters #####
    content = formatcontent(bodyparams)

    # lookup if this route has any registered tags
    if haskey(docs.taggedroutes, path) && httpmethod in docs.taggedroutes[path].httpmethods
        tags = docs.taggedroutes[path].tags
    else
        tags = []
    end

    responses = Dict(
        "200" => Dict{String,Any}("description" => "200 response"),
        "500" => Dict{String,Any}("description" => "500 Server encountered a problem")
        )
        
    # Build a response type payload
    return_types = []
    for item in returntype
        # Structs are typically returning as ::Union{T,Nothing} so extract the concrete type
        inner_type = extract_concrete_types(item)
        
        if !isnothing(inner_type)
            _, inner_types = inner_type
            append!(return_types, inner_types)
        else
            push!(return_types, item)
        end
    end
    
    # Attempt to build schemas for all return types, filtering out those which cannot be built
    return_type_schemas = filter(x -> !isnothing(x), map(x -> buildschema!(x, schemas), return_types))
    json_response_schema = Dict()
    
    # If our function returns multiple types, then may this an `anyOf` collection
    if length(return_type_schemas) > 1 
        json_response_schema = Dict("anyOf" => return_type_schemas)
    elseif length(return_type_schemas) == 1
        json_response_schema = return_type_schemas[1]
    end

    # Only append the content key if we have concrete return type
    if !isempty(json_response_schema)
        responses["200"]["content"] = Dict("application/json" => Dict("schema" => json_response_schema))
    end

    # Build the route schema
    route = Dict(
        "tags" => tags,
        "parameters" => params,
        "responses" => responses
    )

    # Add a request body to the route if it's a POST, PUT, or PATCH request
    if httpmethod in ["POST", "PUT", "PATCH"] || !isempty(bodyparams)
        route["requestBody"] = Dict(
            # if any body param is required, mark the entire body as required
            "required" => any(p -> isrequired(p), bodyparams),
            "content" => content
        )
    end

    if !isempty(schemas)
        mergeschema(docs.schema, Dict("components" => Dict("schemas" => schemas)))
    end

    # remove any special regex patterns from the path before adding this path to the schema
    cleanedpath = replace(path, r"(?=:)(.*?)(?=}/)" => "")
    mergeschema(docs.schema, cleanedpath, Dict("$(lowercase(httpmethod))" => route))
end



function collectschemarefs(data::Dict, keys::Vector{String}; schematype="allOf")
    refs = []
    for key in keys
        if haskey(data, key)
            append!(refs, data[key])
        end
    end
    return Dict("$schematype" => [ Dict("\$ref" => ref) for ref in refs ])
end

"""
Helper function used to determine if a type is a custom struct and whethere or not
we should do a recurive dive and convertion to openapi schema.
"""
function is_custom_struct(T::Type) :: Bool
    return T.name.module ∉ (Base, Core, Dates) && (isstructtype(T) || isabstracttype(T))
end

"""
Generate a sample datetime string that's compatible with julia. The one provided
by the openapi spec includes timezone information which is not supported by DateTime objects.

- only make the current year dynamic to avoid giving away information about the server start time.
"""
function example_datetime() :: String
    return Dates.format(now(), "yyyy") * "-01-01T00:00:00.000"
end

"""
Generates the OpenAPI schema defintion just for the passed type.

If this is an object will generate object definition (and add to `schemas`) 
and return `\$ref` reference, else will create an inline type definition.
"""
function buildschema!(current_type::Type, schemas::Dict)::Union{Dict,Nothing}
    
    # Union{} is the type of html() function 
    if isnothing(current_type) || current_type === Union{}
        return nothing
    end

    current_field = Dict()

    # Handle a nullable type, defined as a Union of {T, Missing|Nothing}
    union_info = extract_concrete_types(current_type)
    if !isnothing(union_info) 
        nullable, non_null_types = union_info
        if nullable 
            current_field["nullable"] = true
        end

        if length(non_null_types) != 1 
            @warn "OpenAPI Nullable union must have exactly one non-nulled type."
            return nothing
        end
        # Re-assign the current type to be in the non-missing type
        current_type = non_null_types[1]
    end
    
    current_name = string(nameof(current_type))    

    # Case 1: Recursively convert nested structs & register schemas
    if is_custom_struct(current_type)
        current_field["\$ref"] = getcomponent(current_name)
        if !haskey(schemas, current_name)
            convertobject!(current_type, schemas)
        end

    # Case 2: The custom type is wrapped inside an array or vector
    elseif current_type <: AbstractVector

        current_field["type"] = "array"
        current_field["items"] = Dict()
        nested_type = current_type.parameters[1]
        nested_type_name = string(nameof(nested_type))

        # Handle custom structs
        if is_custom_struct(nested_type)
            current_field["items"] = Dict("\$ref" => getcomponent(nested_type_name))
            # Register type only if not already registered
            if !haskey(schemas, nested_type_name)
                convertobject!(nested_type, schemas)
            end

        # Handle non-custom nested types
        else
            current_field["items"] = Dict("type" =>  gettype(nested_type))
            format = getformat(nested_type)
            
            if !isnothing(format)
                current_field["items"]["format"] = format
            end

            # Add compatible example format for datetime objects within a vector
            if nested_type <: DateTime
                current_field["items"]["example"] = example_datetime()
                current_field["items"]["description"] = datetime_hint()
            end

        end

    # Case 3: Convert the individual fields of the current type to it's openapi equivalent
    else

        current_field["type"] = gettype(current_type)

        # Add compatible example format for datetime objects
        if current_type <: DateTime
            current_field["example"] = example_datetime()
            current_field["description"] = datetime_hint()
        end

        # Add format if it exists
        format = getformat(current_type)
        if !isnothing(format)
            current_field["format"] = format
        end

    end   

    return current_field
end

"""
Test if this is a union and if so return nullability and non-null types.
Returns `Nothing` if not a union.
"""
function extract_concrete_types(maybe_union)::Union{Tuple{Bool, Vector{Type}}, Nothing}
    if maybe_union isa Union
        sub_types = Base.uniontypes(maybe_union)
        is_nullable = Missing ∈ sub_types || Nothing ∈ sub_types
        non_null_types = filter(x -> x != Nothing && x != Missing, sub_types)
        return (is_nullable, non_null_types)
    end
    return nothing
end

# takes a struct and converts it into an openapi 3.0 compliant dictionary
function convertobject!(type::Type, schemas::Dict) :: Dict

    typename = type |> nameof |> string

    # intilaize this entry
    obj = Dict("type" => "object", "properties" => Dict())
    required_fields = String[]

    # parse out the fields of the type
    info = splitdef(type)

    # Make sure we have a unique set of names (in case of duplicate field names when parsing types)
    # The same field names can show up as regular parameters and keyword parameters when the type is used with @kwdef
    sig_names = OrderedSet{Symbol}(p.name for p in info.sig)

    # loop over all unique fields
    for name in sig_names

        p = info.sig_map[name]
        field_name = string(p.name)
        
        current_type = p.type
        schema = buildschema!(current_type, schemas)

        # Was unable to generate a definition for these field
        if isnothing(schema)
            @warn "AutoDoc unable generate a schema for $typename.$field_name"
            continue;
        end

        if p.hasdefault
            schema["default"] = JSON3.write(p.default) # for special defaults we need to convert to JSON
        end
            
        # TODO: Switch to using nullable property
        if isrequired(p) && (!haskey(schema, "nullable") || schema["nullable"] == false)
            push!(required_fields, field_name);
        end
        
        obj["properties"][field_name] = schema
        
    end
    
    # Required fields cannot be an empty collection so define property only if we have data 
    if length(required_fields) > 0 
        obj["required"] = required_fields
    end

    schemas[typename] = obj

    return schemas
end

"""
Read in a static file from the /data folder
"""
function readstaticfile(filepath::String)::String
    path = joinpath(DATA_PATH, filepath)
    return read(path, String)
end


function redochtml(schemapath::String, docspath::String) :: HTTP.Response
    redocjs = readstaticfile("$REDOC_VERSION/redoc.standalone.js")

    html("""
    <!DOCTYPE html>
    <html lang="en">

        <head>
            <title>Docs</title>
            <meta charset="utf-8"/>
            <meta name="description" content="Docs" />
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <link rel="icon" type="image/x-icon" href="$docspath/metrics/favicon.ico">
        </head>
        
        <body>
            <redoc spec-url="$schemapath"></redoc>
            <script>$redocjs</script>
        </body>

    </html>
    """)
end


"""
Return HTML page to render the autogenerated docs
"""
function swaggerhtml(schemapath::String, docspath::String) :: HTTP.Response

    # load static content files
    swaggerjs = readstaticfile("$SWAGGER_VERSION/swagger-ui-bundle.js")
    swaggerstyles = readstaticfile("$SWAGGER_VERSION/swagger-ui.css")

    html("""
        <!DOCTYPE html>
        <html lang="en">
        
        <head>
            <title>Docs</title>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <meta name="description" content="Docs" />
            <style>$swaggerstyles</style>
            <link rel="icon" type="image/x-icon" href="$docspath/metrics/favicon.ico">
        </head>
        
        <body>
            <div id="swagger-ui"></div>
            <script>$swaggerjs</script>
            <script>
                window.onload = () => {
                    window.ui = SwaggerUIBundle({
                        url: "$schemapath",
                        dom_id: '#swagger-ui',
                    });
                };
            </script>
        </body>
        
        </html>
    """)
end

end
