from pyspark.sql import SparkSession
import uuid 
import warnings
from pyspark.sql.column import Column, _to_java_column
from pyspark.sql.types import _parse_datatype_json_string
from pyspark.sql import functions as f


warnings.filterwarnings('ignore')
app_name = uuid.uuid1().hex
spark = (SparkSession.builder
        .appName(app_name)
        .config("spark.jars.packages", "org.apache.hadoop:hadoop-aws:3.3.1,com.databricks:spark-xml_2.12:0.18.0")
        .getOrCreate()
        )

spark._jsc.hadoopConfiguration().set("fs.s3a.access.key", "")
spark._jsc.hadoopConfiguration().set("fs.s3a.secret.key", "")
spark._jsc.hadoopConfiguration().set("fs.s3a.endpoint", "s3.amazonaws.com")

def ext_from_xml(xml_column, schema, options={}):
    java_column = _to_java_column(xml_column.cast('string'))
    java_schema = spark._jsparkSession.parseDataType(schema.json())
    scala_map = spark._jvm.org.apache.spark.api.python.PythonUtils.toScalaMap(options)
    jc = spark._jvm.com.databricks.spark.xml.functions.from_xml(
        java_column, java_schema, scala_map)
    return Column(jc)

def ext_schema_of_xml_df(df, options={}):
    assert len(df.columns) == 1

    scala_options = spark._jvm.PythonUtils.toScalaMap(options)
    java_xml_module = getattr(getattr(
        spark._jvm.com.databricks.spark.xml, "package$"), "MODULE$")
    java_schema = java_xml_module.schema_of_xml_df(df._jdf, scala_options)
    return _parse_datatype_json_string(java_schema.json())

df = spark.read.parquet("s3://vendor1-t24-parsing/topics/POC.T24_EBF_EFICAZ_REQUESTS/")

schema = ext_schema_of_xml_df(df.select("after_XMLRECORD"))

df.withColumn("parse", ext_from_xml(f.col("after_XMLRECORD"), schema)).select("parse.*").limit(10).show()