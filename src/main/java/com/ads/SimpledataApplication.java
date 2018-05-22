package com.ads;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.web.support.SpringBootServletInitializer;
import org.springframework.context.annotation.Bean;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.PlatformTransactionManager;

import javax.sql.DataSource;

@SpringBootApplication
@MapperScan("com.ads.mapper")//将项目中对应的mapper类的路径加进来
public class SimpledataApplication extends SpringBootServletInitializer {

	public static void main(String[] args) {
		SpringApplication.run(SimpledataApplication.class, args);
	}

	protected SpringApplicationBuilder configure(SpringApplicationBuilder application){
		return application.sources(SimpledataApplication.class);
	}

	@Bean
	public PlatformTransactionManager txManager(DataSource dataSource) {
		return new DataSourceTransactionManager(dataSource);
	}
}
