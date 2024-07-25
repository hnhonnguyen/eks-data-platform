from pyspark.sql import SparkSession
from pyspark.sql.functions import *
import uuid 


import warnings
warnings.filterwarnings('ignore')
app_name = uuid.uuid1().hex
spark = (SparkSession.builder
.appName(app_name)
.getOrCreate()
)

output = spark.sql('''select 1''').collect()

print(output)

spark.stop()