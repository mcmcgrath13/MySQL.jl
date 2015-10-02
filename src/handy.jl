# Handy wrappers to functions defined in api.jl.

"""
A handy function that wraps mysql_init and mysql_real_connect. Also does error
checking on the pointers returned by init and real_connect.
"""
function mysql_init_and_connect(host::String,
                                  user::String,
                                  passwd::String,
                                  db::String,
                                  port::Integer = 0,
                                  unix_socket::Any = C_NULL,
                                  client_flag::Integer = 0)

    mysqlptr::MYSQL = C_NULL
    mysqlptr = mysql_init(mysqlptr)

    if mysqlptr == C_NULL
        error("Failed to initialize MySQL database")
    end

    mysqlptr = mysql_real_connect(mysqlptr,
                                  host,
                                  user,
                                  passwd,
                                  db,
                                  convert(Cint, port),
                                  unix_socket,
                                  convert(Uint64, client_flag))

    if mysqlptr == C_NULL
        error("Failed to connect to MySQL database")
    end

    return MySQLDatabaseHandle(mysqlptr, 0)
end

"""
Wrapper over mysql_real_connect with CLIENT_MULTI_STATEMENTS passed
as client flag options.
"""
function mysql_init_and_connect(hostName::String, userName::String, password::String, db::String)
    return mysql_init_and_connect(hostName, userName, password, db, 0,
                                  C_NULL, MySQL.CLIENT_MULTI_STATEMENTS)
end

"""
Wrapper over mysql_close. Must be called to close the connection opened by
MySQL.mysql_connect.
"""
function mysql_disconnect(db::MySQLDatabaseHandle)
    mysql_close(db.ptr)
end

"""
Execute a query and return results as a dataframe if the query was a select query.
If query is not a select query then return the number of affected rows.
"""
function execute_query(con::MySQLDatabaseHandle, command::String)
    response = MySQL.mysql_query(con.ptr, command)
    mysql_display_error(con, response != 0,
                        "Error occured while executing mysql_query on \"$command\"")

    results = MySQL.mysql_store_result(con.ptr)
    if (results == C_NULL)
        affectedRows = MySQL.mysql_affected_rows(con.ptr)
        return affectedRows
    end

    dframe = MySQL.results_to_dataframe(results)
    MySQL.mysql_free_result(results)
    return dframe
end

"""
Same as execute query but for multi-statements.
"""
function execute_multi_query(con::MySQLDatabaseHandle, command::String)
    # Ideally, we should find out what the current auto-commit mode is
    # before setting/unsetting it.
    MySQL.mysql_autocommit(con.ptr, convert(Int8, 0))

    response = MySQL.mysql_query(con.ptr, command)
    mysql_display_error(con, response != 0,
                        "Error occured while executing mysql_query on \"$command\"")

    results = MySQL.mysql_store_result(con.ptr)
    
    if (results == C_NULL)
        affectedRows = 0

        while (MySQL.mysql_next_result(con.ptr) == 0)
            affectedRows = affectedRows + MySQL.mysql_affected_rows(con.ptr)
        end

        MySQL.mysql_autocommit(con.ptr, convert(Int8, 1))
        return affectedRows
    end

    MySQL.mysql_autocommit(con.ptr, convert(Int8, 1))
    dframe = MySQL.results_to_dataframe(results)
    MySQL.mysql_free_result(results)
    return dframe
end

"""
A handy function to display the `mysql_error` message along with a user message `msg` through `error`
 when `condition` is true.
"""
function mysql_display_error(con, condition, msg)
    if (condition)
        err_string = msg * "\nMySQL ERROR: " * bytestring(MySQL.mysql_error(con.ptr))
        error(err_string)
    end
end

"""
Given a prepared statement pointer `stmtptr` returns a dataframe containing the results.
`mysql_stmt_prepare` must be called on the statement pointer before this can be used.
"""
function stmt_results_to_dataframe(stmtptr::Ptr{MYSQL_STMT})
    stmt = unsafe_load(stmtptr)
    metadata = MySQL.mysql_stmt_result_metadata(stmtptr)
    mysql_display_error(stmt.mysql, metadata == C_NULL,
                        "Error occured while retrieving metadata")

    response = MySQL.mysql_stmt_execute(stmtptr)
    mysql_display_error(stmt.mysql, response != 0,
                        "Error occured while executing prepared statement")

    return MySQL.stmt_results_to_dataframe(metadata, stmtptr)
end
