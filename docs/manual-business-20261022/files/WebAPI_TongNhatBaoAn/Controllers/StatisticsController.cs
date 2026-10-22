using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using WebAPI_TongNhatBaoAn.Models;
using WebAPI_TongNhatBaoAn.Services;
namespace WebAPI_TongNhatBaoAn.Controllers;

[ApiController, Route("api/statistics"), Authorize]
public sealed class StatisticsController(StatisticsService stats) : ApiBase
{
    [HttpGet("mine")]
    public async Task<IActionResult> Mine(DateOnly from, DateOnly to) => Ok(await stats.Personal(UserId,from,to));
    [HttpGet("company"), Authorize(Roles = Roles.AdminOrManager)]
    public async Task<IActionResult> Company(DateOnly from, DateOnly to) => Ok(await stats.Company(from,to));
}
