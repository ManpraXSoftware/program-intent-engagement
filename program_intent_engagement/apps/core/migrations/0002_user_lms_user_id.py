# Generated by Django 3.2.13 on 2022-06-23 14:25

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('core', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='user',
            name='lms_user_id',
            field=models.IntegerField(db_index=True, null=True),
        ),
    ]
