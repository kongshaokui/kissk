package com.ads.mapper;

import com.ads.model.Report;

public interface ReportMapper {
    int deleteByPrimaryKey(Integer id);

    int insert(Report record);

    int insertSelective(Report record);

    Report selectByPrimaryKey(Integer id);

    int updateByPrimaryKeySelective(Report record);

    int updateByPrimaryKey(Report record);
}