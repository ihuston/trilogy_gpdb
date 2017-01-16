# Trilogy and Greenplum

Today I'm going to show you how you can use a new SQL testing framework called
[Trilogy](https://github.com/PivotalSharedIreland/trilogy)
with the open source [Greenplum Database](http://greenplum.org/) to help you
[test drive](http://engineering.pivotal.io/post/test-driven-development-for-data-science/)
your data science code.

## Background
As a data scientist at Pivotal I write a lot of SQL and I write a lot of tests.
Doing both at the same time has always been a bit difficult. Some SQL databases
have testing frameworks like PGTap or Oracle SQL Developer tool, but these
are rarely easy to set up and work with on a real system.

In the past I have leveraged other programming languages like Python, R or even Bash
to run simple SQL test suites and make them part of our CI pipeline.
I would spend some time at the start of each project getting this setup working
but it would always be somewhat hard-coded for the project at hand,
and be difficult for new team members to understand without a lot of effort.

My colleagues Konstantin and Cassio faced a similar problem recently and decided to do something about it,
by [building a generic testing framework](http://engineering.pivotal.io/post/oracle-sql-tdd/) for databases called [Trilogy](https://github.com/PivotalSharedIreland/trilogy).

Trilogy is written in Java, but can be used simply from the command line, and
can connect to any database with a JDBC driver (which is pretty much all of them).
A key feature of Trilogy is that tests are written in SQL wrapped in a
simple Markdown template, so that there is no cognitive dissonance between the
code you are testing in SQL and the test itself.

If you use Oracle, PostgreSQL or any other database you can get started with Trilogy
by following [the README](https://github.com/PivotalSharedIreland/trilogy/blob/master/README.md).

As a data scientist [test driving](http://engineering.pivotal.io/post/test-driven-development-for-data-science/) my code,
I often use the open source
[Greenplum Database](http://greenplum.org/) or its commercial counterpart
[Pivotal Greenplum](https://pivotal.io/big-data/pivotal-greenplum).
Greenplum is a Massively Parallel Processing (MPP) database, and started as a
fork from PostgreSQL around version 8.2. This means that many of the normal
PostgreSQL tools like `psql` or JDBC drivers from PostgreSQL can be used easily
with Greenplum.

PostgreSQL and Greenplum have developed in different directions in the intervening years
however, so sometimes there are recent features from PostgreSQL that are not available in
Greenplum (and vice versa of course).

In particular for the Trilogy testing framework, the easiest way to write tests
is to run an anonymous code block and raise an exception if the test fails.
In the Markdown structure that Trilogy uses this would look like:
```
# TEST CASE
A simple test of multiplication
## TEST
This is the test
\`\`\`
DO $$
BEGIN
    SELECT CASE WHEN 2*3=6 THEN NULL
    ELSE RAISE EXCEPTION 'Failed to multiple!';
END
$$;
\`\`\`
```

Unfortunately the `DO` statement was added to PostgreSQL in version 9.0 and
is not available in Greenplum. In this post I am going to describe how you can
still use Trilogy with Greenplum without needing `DO`.


## Installing Greenplum
- Clone the repo including Docker file from https://github.com/dbbaskette/gpdb-docker.
- Follow the instructions to download Greenplum from the Pivotal website.
- Build the docker image using
```
docker build -t [tag] .
```
where tag is how you will refer to the build (e.g. 'gpdb').

- Start the Greenplum server using
```
docker run -i -p 5432:5432 [tag]
```
- Check the server is running using `psql`. The password for `gpadmin` is `pivotal`:
```
psql -U gpadmin -h localhost -p 5432
```
- Run the following SQL query to see the version of Greenplum:
```
SELECT version();
```
If everything has worked you should see something like:
```
gpadmin=# select version();
                                                                       version
------------------------------------------------------------------------------------------------------------------------------------------------------
 PostgreSQL 8.2.15 (Greenplum Database 4.3.7.1 build 1) on x86_64-unknown-linux-gnu, compiled by GCC gcc (GCC) 4.4.2 compiled on Jan 21 2016 15:51:02
(1 row)
```

## Building Trilogy
- Clone repo from https://github.com/PivotalSharedIreland/trilogy.
- If you don't want to build it yourself, download the JAR from https://github.com/PivotalSharedIreland/trilogy/releases.
- Otherwise follow instructions to build Trilogy using Gradle.

## Setting up Trilogy

- First create a new database for this testing in psql:
```
CREATE database testing;
```
- Switch to this database in `psql` using `\c testing`.
- If you don't have the PostgreSQL JDBC driver installed get it from https://jdbc.postgresql.org/download.html.

## Our first test
Create a file called `simple.stt` as a simple first test:
```
# TEST CASE
Our first test
## TEST
This is the test
\`\`\`
SELECT 1;
\`\`\`
```

Run this test using Trilogy:
```
java -jar trilogy.jar --db_url=jdbc:postgresql://localhost:5432/testing --db_user=gpadmin --db_password=pivotal ./simple.stt
```
If you need to provide the PostgreSQL JDBC driver using a Classpath then the entry point for the Java application changes:
```
java -classpath /PATH/TO/JDBC/DRIVER/postgresql-9.4.1212.jar:/PATH/TO/TRILOGY/trilogy.jar org.springframework.boot.loader.JarLauncher --db_url=jdbc:postgresql://localhost:5432/testing --db_user=gpadmin --db_password=pivotal ./simple.stt
```

You should see the Trilogy logo and a successful result:
```
SUCCEEDED
Total: 1, Passed: 1, Failed: 0
```

## A Failing test
Trilogy test cases assume that anything that doesn't raise an exception is a passing test.
Our next goal is to get a test to fail. To do this we need to use the [`RAISE` statement](https://www.postgresql.org/docs/8.2/static/plpgsql-errors-and-messages.html) that
is part of PL/PGSQL.

From [PostgreSQL 9.0](https://www.postgresql.org/docs/9.0/static/sql-do.html) onwards, it is possible to have an anonymous block of PL/PGSQL code,
which makes writing these tests very efficient:
```
DO $$
BEGIN
    SELECT CASE WHEN 2*3=6 THEN NULL
    ELSE RAISE EXCEPTION 'Failed to multiple!';
END
$$;
```
Unfortunately Greenplum does not include the `DO` command so we need to allow some way to
`RAISE` an exception from PL/PGSQL, preferably without creating a new function for each test.

One way to do this is to create two void functions, `pass()` and `fail()`, and call these
as needed inside our tests. To create these functions run the following inside `psql`:
```
CREATE OR REPLACE FUNCTION fail()
RETURNS VOID AS
$$
BEGIN
RAISE EXCEPTION 'FAIL';
END;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION pass()
RETURNS VOID AS
$$
BEGIN
NULL;
END;
$$ language plpgsql;
```

You can see how this works by trying the following statement in `psql`:
```
SELECT fail();
```
You should see `ERROR:  FAIL` as the response.

We're now ready to create a failing test in `failing.stt`:
```
# TEST CASE
A failing test
## TEST
This test should fail
\`\`\`
SELECT CASE WHEN 2*3=7 THEN pass() ELSE fail() END;
\`\`\`
```

You can run this test using Trilogy as before:
```
java -jar trilogy.jar --db_url=jdbc:postgresql://localhost:5432/testing --db_user=gpadmin --db_password=pivotal ./failing.stt
```

You should see the test fail with our test description included in the output.
```
[FAIL] A failing test - This test should fail:
    StatementCallback; uncategorized SQLException for SQL [SELECT CASE WHEN 2*3=7 THEN pass() ELSE fail() END]; SQL state [P0001]; error code [0]; ERROR: FAIL; nested exception is org.postgresql.util.PSQLException: ERROR: FAIL
FAILED
Total: 1, Passed: 0, Failed: 1
```

## Testing a data science project
For real world use cases you need to go beyond testing a single SQL statement
inside a specific test file. Trilogy allows you to test a whole project,
with overall database schema and test setup and teardown scripts.

The instructions in the Trilogy README explain how a project should be laid out,
and the repo accompanying this post has an example of one for a Greenplum database.
With this set up your test script can specify when to execute setup and
teardown scripts and you can test user defined functions that you have added
to your database.

Consider the following function that we want to add to a customer transactions
database to check the consistency of the customer balance:
```
CREATE OR REPLACE FUNCTION VALIDATE_BALANCE(
  V_CLIENT_ID INT) RETURNS BOOL AS $$
DECLARE
  IS_VALID BOOLEAN;
BEGIN
  SELECT CASE C.BALANCE - COALESCE(SUM(T.VALUE), '0') WHEN '0' THEN TRUE ELSE FALSE END INTO IS_VALID
    FROM CLIENTS C LEFT JOIN TRANSACTIONS T ON T.ID_CLIENT=C.ID WHERE C.ID=V_CLIENT_ID GROUP BY C.ID, C.BALANCE;
  RETURN IS_VALID;
END;
$$ LANGUAGE plpgsql;
```

To test this function in an isolated testing database we need to
- Create a `clients` table and a `transactions` table. This happens in `schema.sql`.
- Insert some client test data before we run any tests.
- Insert specific transactions and balance before each test.
- Run our test.
- After each test, remove the transactions and balances as needed to create a clean environment for the next test.
- After all the tests are complete, remove the clients we have added.

We can specify when to run each setup and teardown script inside our test
specification file `generic_testcase.stt`:
```
# TEST CASE
Generic test case example
## BEFORE ALL
- Setup client
## BEFORE EACH TEST
- Set client balance
## AFTER EACH TEST
- Remove transactions
## AFTER ALL
- Remove clients
## TEST
This test should fail
\`\`\`
SELECT
  CASE WHEN (1 <> 2) THEN
    fail() -- This should never have happened
  END
FROM clients where ID=66778899
;
\`\`\`
## TEST
This test should pass
\`\`\`
SELECT
    CASE WHEN VALIDATE_BALANCE(66778899) THEN pass()
    ELSE fail() END;
\`\`\`
## TEST
And this test should pass
\`\`\`
SELECT 1;
\`\`\`

```

The lines
```
## BEFORE EACH TEST
- Set client balance
```
state that we should run the client balance setup script before each test invocation.
The name of this script is determined from the second line and could be
`set_client_balance.sql`, `setclientbalance.sql` or similar.

As your data science SQL code grows, this project structure allows you to flexibly
add schemas and fixture scripts as needed.

## Summary
In my opinion Trilogy is an interesting new testing framework for SQL databases that
solves some of the issues with other frameworks. Having shown how it can work with
Greenplum databases I'm looking forward to making use of it in a future
client project!
